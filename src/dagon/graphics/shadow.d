/*
Copyright (c) 2017 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.graphics.shadow;

import std.stdio;
import std.math;
import std.conv;

import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.math.interpolation;
import dlib.image.color;
import dlib.image.unmanaged;
import dlib.image.render.shapes;

import derelict.opengl;

import dagon.core.interfaces;
import dagon.core.ownership;
import dagon.logics.entity;
import dagon.logics.behaviour;
import dagon.graphics.shapes;
import dagon.graphics.texture;
import dagon.graphics.view;
import dagon.graphics.rc;
import dagon.graphics.environment;
import dagon.graphics.material;
import dagon.graphics.materials.generic;
import dagon.resource.scene;

class ShadowArea: Owner
{
    Environment environment;
    Matrix4x4f biasMatrix;
    Matrix4x4f projectionMatrix;
    Matrix4x4f viewMatrix;
    Matrix4x4f invViewMatrix;
    Matrix4x4f shadowMatrix;
    float width;
    float height;
    float depth;
    float start;
    float end;
    float scale = 1.0f;
    Vector3f position;

    this(Environment env, float w, float h, float start, float end, Owner o)
    {
        super(o);   
        this.width = w;
        this.height = h;
        this.start = start;
        this.end = end;        
        this.environment = env;

        depth = abs(start) + abs(end);
        
        this.position = Vector3f(0, 0, 0);

        this.biasMatrix = matrixf(
            0.5f, 0.0f, 0.0f, 0.5f,
            0.0f, 0.5f, 0.0f, 0.5f,
            0.0f, 0.0f, 0.5f, 0.5f,
            0.0f, 0.0f, 0.0f, 1.0f,
        );

        float hw = w * 0.5f;
        float hh = h * 0.5f;
        this.projectionMatrix = orthoMatrix(-hw, hw, -hh, hh, start, end);
        
        this.shadowMatrix = Matrix4x4f.identity;
        this.viewMatrix = Matrix4x4f.identity;
        this.invViewMatrix = Matrix4x4f.identity;
    }

    void update(RenderingContext* rc, double dt)
    {
        auto t = translationMatrix(position);
        auto r = environment.sunRotation.toMatrix4x4;
        invViewMatrix = t * r;
        viewMatrix = invViewMatrix.inverse;
        shadowMatrix = scaleMatrix(Vector3f(scale, scale, 1.0f)) * biasMatrix * projectionMatrix * viewMatrix * rc.invViewMatrix; // view.invViewMatrix;
    }
}

class ShadowBackend: GLSLMaterialBackend
{
    
    string vsText = 
    q{
        #version 330 core

        uniform mat4 modelViewMatrix;
        uniform mat4 projectionMatrix;
        
        layout (location = 0) in vec3 va_Vertex;
        
        void main()
        {
            gl_Position = projectionMatrix * modelViewMatrix * vec4(va_Vertex, 1.0);
        }
    };
    
    string fsText =
    q{
        #version 330 core

        out vec4 frag_color;
        
        void main()
        {
            frag_color = vec4(1.0, 1.0, 1.0, 1.0);
        }
    };
    
    override string vertexShaderSrc() {return vsText;}
    override string fragmentShaderSrc() {return fsText;}

    GLint modelViewMatrixLoc;
    GLint projectionMatrixLoc;
    
    this(Owner o)
    {
        super(o);

        modelViewMatrixLoc = glGetUniformLocation(shaderProgram, "modelViewMatrix");
        projectionMatrixLoc = glGetUniformLocation(shaderProgram, "projectionMatrix");
    }
    
    override void bind(GenericMaterial mat, RenderingContext* rc)
    {        
        glDisable(GL_CULL_FACE);
        
        glUseProgram(shaderProgram);

        glUniformMatrix4fv(modelViewMatrixLoc, 1, GL_FALSE, rc.modelViewMatrix.arrayof.ptr);
        glUniformMatrix4fv(projectionMatrixLoc, 1, GL_FALSE, rc.projectionMatrix.arrayof.ptr);
    }
    
    override void unbind(GenericMaterial mat)
    {        
        glUseProgram(0);
    }
}

class CascadedShadowMap: Owner
{
    uint size;
    BaseScene3D scene;
    ShadowArea area1;
    ShadowArea area2;
    ShadowArea area3;
    
    GLuint depthTexture;
    GLuint framebuffer1;
    GLuint framebuffer2;
    GLuint framebuffer3;
    
    ShadowBackend sb;
    Material sm;
    
    float projSize1 = 10.0f;
    float projSize2 = 50.0f;
    float projSize3 = 400.0f;
    
    float zStart = -100.0f;
    float zEnd = 100.0f;

    this(uint size, BaseScene3D scene, float projSizeNear, float projSizeMid, float projSizeFar, float zStart, float zEnd, Owner o)
    {
        super(o);
        this.size = size;
        this.scene = scene;
        
        projSize1 = projSizeNear;
        projSize2 = projSizeMid;
        projSize3 = projSizeFar;
        
        this.zStart = zStart;
        this.zEnd = zEnd;

        this.area1 = New!ShadowArea(scene.environment, projSize1, projSize1, zStart, zEnd, this);
        this.area2 = New!ShadowArea(scene.environment, projSize2, projSize2, zStart, zEnd, this);
        this.area3 = New!ShadowArea(scene.environment, projSize3, projSize3, zStart, zEnd, this);
        
        this.sb = New!ShadowBackend(this);
        this.sm = New!GenericMaterial(sb, this);

        glGenTextures(1, &depthTexture);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D_ARRAY, depthTexture);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);

        Color4f borderColor = Color4f(1, 1, 1, 1);
        
        glTexParameterfv(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_BORDER_COLOR, borderColor.arrayof.ptr);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
	    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL);

        glTexImage3D(GL_TEXTURE_2D_ARRAY, 0, GL_DEPTH_COMPONENT24, size, size, 3, 0, GL_DEPTH_COMPONENT, GL_FLOAT, null);
        
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_BASE_LEVEL, 0);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_LEVEL, 0);
        
        glBindTexture(GL_TEXTURE_2D_ARRAY, 0);

        glGenFramebuffers(1, &framebuffer1);
	    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer1);
        glDrawBuffer(GL_NONE);
	    glReadBuffer(GL_NONE);
        glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, depthTexture, 0, 0);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        
        glGenFramebuffers(1, &framebuffer2);
	    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer2);
        glDrawBuffer(GL_NONE);
	    glReadBuffer(GL_NONE);
        glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, depthTexture, 0, 1);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        
        glGenFramebuffers(1, &framebuffer3);
	    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer3);
        glDrawBuffer(GL_NONE);
	    glReadBuffer(GL_NONE);
        glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, depthTexture, 0, 2);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
    
    Vector3f position()
    {
        return area1.position;
    }
    
    void position(Vector3f pos)
    {
        area1.position = pos;
        area2.position = pos;
        area3.position = pos;
    }
    
    ~this()
    {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glDeleteFramebuffers(1, &framebuffer1);
        glDeleteFramebuffers(1, &framebuffer2);
        glDeleteFramebuffers(1, &framebuffer3);
        
        if (glIsTexture(depthTexture))
            glDeleteTextures(1, &depthTexture);
    }
    
    void update(RenderingContext* rc, double dt)
    {
        area1.update(rc, dt);
        area2.update(rc, dt);
        area3.update(rc, dt);
    }
    
    void render(RenderingContext* rc)
    {        
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer1);

        glViewport(0, 0, size, size);
        glScissor(0, 0, size, size);
        glClear(GL_DEPTH_BUFFER_BIT);
        
        glEnable(GL_DEPTH_TEST);

        auto rcLocal = *rc;
        rcLocal.projectionMatrix = area1.projectionMatrix;
        rcLocal.viewMatrix = area1.viewMatrix;
        rcLocal.invViewMatrix = area1.invViewMatrix;
        rcLocal.normalMatrix = rcLocal.invViewMatrix.transposed;
        
        rcLocal.overrideMaterial = sm;

        glPolygonOffset(3.0, 0.0);
        glDisable(GL_CULL_FACE);
        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);

        foreach(e; scene.entities3D)
            if (e.castShadow)
                e.render(&rcLocal);
         
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer2);

        glViewport(0, 0, size, size);
        glScissor(0, 0, size, size);
        glClear(GL_DEPTH_BUFFER_BIT);

        rcLocal.projectionMatrix = area2.projectionMatrix;
        rcLocal.viewMatrix = area2.viewMatrix;
        rcLocal.invViewMatrix = area2.invViewMatrix;
        rcLocal.normalMatrix = rcLocal.invViewMatrix.transposed;

        foreach(e; scene.entities3D)
            if (e.castShadow)
                e.render(&rcLocal);
        
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer3);

        glViewport(0, 0, size, size);
        glScissor(0, 0, size, size);
        glClear(GL_DEPTH_BUFFER_BIT);

        rcLocal.projectionMatrix = area3.projectionMatrix;
        rcLocal.viewMatrix = area3.viewMatrix;
        rcLocal.invViewMatrix = area3.invViewMatrix;
        rcLocal.normalMatrix = rcLocal.invViewMatrix.transposed;

        foreach(e; scene.entities3D)
            if (e.castShadow)
                e.render(&rcLocal);
        
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glEnable(GL_CULL_FACE);
        glPolygonOffset(0.0, 0.0);
        
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
}
