/*
Copyright (c) 2018 Timur Gafarov

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

module dagon.graphics.shaders.probepass;

import std.stdio;
import std.math;

import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.image.color;

import dagon.core.libs;
import dagon.core.ownership;
import dagon.graphics.rc;
import dagon.graphics.shader;
import dagon.graphics.gbuffer;
import dagon.graphics.probe;

class ProbePassShader: Shader
{
    string vs = import("ProbePass.vs");    
    string fs = import("ProbePass.fs");
    
    GBuffer gbuffer;
    EnvironmentProbe probe;
    
    this(GBuffer gbuffer, Owner o)
    {    
        auto myProgram = New!ShaderProgram(vs, fs, this);
        super(myProgram, o);
        this.gbuffer = gbuffer;
    }
    
    void bind(RenderingContext* rc2d, RenderingContext* rc3d)
    {
        setParameter("viewMatrix", rc3d.viewMatrix);
        setParameter("invViewMatrix", rc3d.invViewMatrix);
        setParameter("projectionMatrix", rc3d.projectionMatrix);
        setParameter("viewSize", Vector2f(gbuffer.width, gbuffer.height));
        
        // Texture 0 - color buffer
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, gbuffer.colorTexture);
        setParameter("colorBuffer", 0);
        
        // Texture 1 - roughness-metallic-specularity buffer
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, gbuffer.rmsTexture);
        setParameter("rmsBuffer", 1);
        
        // Texture 2 - position buffer
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, gbuffer.positionTexture);
        setParameter("positionBuffer", 2);
        
        // Texture 3 - normal buffer
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, gbuffer.normalTexture);
        setParameter("normalBuffer", 3);
        
        glActiveTexture(GL_TEXTURE0);
        
        if (probe)
        {
            // Texture 4 - cubemap
            glActiveTexture(GL_TEXTURE4);
            glBindTexture(GL_TEXTURE_CUBE_MAP, probe.texture);
            setParameter("cubemap", 4);
        
            Matrix4x4f modelViewMatrix = 
                rc3d.viewMatrix *
                translationMatrix(probe.position) * 
                scaleMatrix(Vector3f(5, 5, 5));
            
            setParameter("modelViewMatrix", modelViewMatrix);
            setParameter("lightPosition", probe.position);
        }
    
        super.bind(rc3d);
    }
    
    void unbind(RenderingContext* rc2d, RenderingContext* rc3d)
    {
        super.unbind(rc3d);
        
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        glActiveTexture(GL_TEXTURE4);
        glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
        
        glActiveTexture(GL_TEXTURE0);
    }
}