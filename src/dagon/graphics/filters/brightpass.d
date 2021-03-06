/*
Copyright (c) 2019 Timur Gafarov

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

module dagon.graphics.filters.brightpass;

import dlib.math.vector;
import dagon.core.libs;
import dagon.core.ownership;
import dagon.graphics.postproc;
import dagon.graphics.framebuffer;
import dagon.graphics.rc;

class PostFilterBrightPass: PostFilter
{
    private string vs = import("BrightPass.vs");
    private string fs = import("BrightPass.fs");
    
    GLint luminanceThresholdLoc;
    float luminanceThreshold = 1.0f;

    override string vertexShader()
    {
        return vs;
    }

    override string fragmentShader()
    {
        return fs;
    }

    this(Framebuffer inputBuffer, Framebuffer outputBuffer, Owner o)
    {
        super(inputBuffer, outputBuffer, o);
        luminanceThresholdLoc = glGetUniformLocation(shaderProgram, "luminanceThreshold");
    }

    override void bind(RenderingContext* rc)
    {
        super.bind(rc);
        glUniform1f(luminanceThresholdLoc, luminanceThreshold);
    }
}
