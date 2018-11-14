/*
Copyright (c) 2017-2018 Timur Gafarov

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

import dagon.core.libs;
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
import dagon.graphics.shaders.shadowpass;
import dagon.resource.scene;

class ShadowArea: Owner
{
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

    this(float w, float h, float start, float end, Owner o)
    {
        super(o);
        this.width = w;
        this.height = h;
        this.start = start;
        this.end = end;

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
        auto r = rc.environment.sunRotation.toMatrix4x4;
        invViewMatrix = t * r;
        viewMatrix = invViewMatrix.inverse;
        shadowMatrix = scaleMatrix(Vector3f(scale, scale, 1.0f)) * biasMatrix * projectionMatrix * viewMatrix * rc.invViewMatrix;
    }
}

class CascadedShadowMap: Owner
{
    uint size;
    ShadowArea area1;
    ShadowArea area2;
    ShadowArea area3;

    GLuint depthTexture;
    GLuint framebuffer1;
    GLuint framebuffer2;
    GLuint framebuffer3;

    ShadowPassShader ss;

    float projSize1 = 5.0f;
    float projSize2 = 15.0f;
    float projSize3 = 400.0f;

    float zStart = -300.0f;
    float zEnd = 300.0f;

    Color4f shadowColor = Color4f(1.0f, 1.0f, 1.0f, 1.0f);
    float shadowBrightness = 0.1f;
    bool useHeightCorrectedShadows = false;

    this(uint size, float projSizeNear, float projSizeMid, float projSizeFar, float zStart, float zEnd, Owner o)
    {
        super(o);
        this.size = size;

        projSize1 = projSizeNear;
        projSize2 = projSizeMid;
        projSize3 = projSizeFar;

        this.zStart = zStart;
        this.zEnd = zEnd;

        this.area1 = New!ShadowArea(projSize1, projSize1, zStart, zEnd, this);
        this.area2 = New!ShadowArea(projSize2, projSize2, zStart, zEnd, this);
        this.area3 = New!ShadowArea(projSize3, projSize3, zStart, zEnd, this);

        this.ss = New!ShadowPassShader(this);

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

    void render(Scene scene, RenderingContext* rc)
    {
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer1);

        glViewport(0, 0, size, size);
        glScissor(0, 0, size, size);
        glClear(GL_DEPTH_BUFFER_BIT);

        glEnable(GL_DEPTH_TEST);

        ss.bindProgram();

        auto rcLocal = *rc;
        rcLocal.projectionMatrix = area1.projectionMatrix;
        rcLocal.viewMatrix = area1.viewMatrix;
        rcLocal.invViewMatrix = area1.invViewMatrix;
        rcLocal.normalMatrix = rcLocal.invViewMatrix.transposed;
        rcLocal.viewRotationMatrix = matrix3x3to4x4(matrix4x4to3x3(rcLocal.viewMatrix));
        rcLocal.invViewRotationMatrix = matrix3x3to4x4(matrix4x4to3x3(rcLocal.invViewMatrix));

        rcLocal.overrideShader = ss;
        rcLocal.shadowPass = true;
        rcLocal.rebindShaderProgram = false;

        glPolygonOffset(3.0, 0.0);
        glDisable(GL_CULL_FACE);
        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);

        foreach(e; scene.entities3D)
            if (e.castShadow)
                e.render(&rcLocal);
        scene.particleSystem.render(&rcLocal);

        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer2);

        glViewport(0, 0, size, size);
        glScissor(0, 0, size, size);
        glClear(GL_DEPTH_BUFFER_BIT);

        rcLocal.projectionMatrix = area2.projectionMatrix;
        rcLocal.viewMatrix = area2.viewMatrix;
        rcLocal.invViewMatrix = area2.invViewMatrix;
        rcLocal.normalMatrix = rcLocal.invViewMatrix.transposed;
        rcLocal.viewRotationMatrix = matrix3x3to4x4(matrix4x4to3x3(rcLocal.viewMatrix));
        rcLocal.invViewRotationMatrix = matrix3x3to4x4(matrix4x4to3x3(rcLocal.invViewMatrix));

        foreach(e; scene.entities3D)
            if (e.castShadow)
                e.render(&rcLocal);
        scene.particleSystem.render(&rcLocal);

        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer3);

        glViewport(0, 0, size, size);
        glScissor(0, 0, size, size);
        glClear(GL_DEPTH_BUFFER_BIT);

        rcLocal.projectionMatrix = area3.projectionMatrix;
        rcLocal.viewMatrix = area3.viewMatrix;
        rcLocal.invViewMatrix = area3.invViewMatrix;
        rcLocal.normalMatrix = rcLocal.invViewMatrix.transposed;
        rcLocal.viewRotationMatrix = matrix3x3to4x4(matrix4x4to3x3(rcLocal.viewMatrix));
        rcLocal.invViewRotationMatrix = matrix3x3to4x4(matrix4x4to3x3(rcLocal.invViewMatrix));

        foreach(e; scene.entities3D)
            if (e.castShadow)
                e.render(&rcLocal);
        scene.particleSystem.render(&rcLocal);

        ss.unbindProgram();

        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glEnable(GL_CULL_FACE);
        glPolygonOffset(0.0, 0.0);

        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
}
