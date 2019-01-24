#version 400 core

uniform sampler2D positionBuffer;

uniform vec2 viewSize;

uniform mat4 invViewMatrix;
uniform mat4 invModelMatrix;

vec3 toLinear(vec3 v)
{
    return pow(v, vec3(2.2));
}

layout(location = 0) out vec4 frag_color;

void main()
{
    vec2 gbufTexCoord = gl_FragCoord.xy / viewSize;

    vec3 eyePos = texture(positionBuffer, gbufTexCoord).xyz;

    vec3 worldPos = (invViewMatrix * vec4(eyePos, 1.0)).xyz;
    vec3 objPos = (invModelMatrix * vec4(worldPos, 1.0)).xyz;

    // Perform bounds check to discard fragments outside the decal box
    vec3 c = vec3(0.0, 1.0, 0.0);
    if (abs(objPos.x) > 1.0) c = vec3(1.0, 0.0, 0.0);
    if (abs(objPos.y) > 1.0) c = vec3(1.0, 0.0, 0.0);
    if (abs(objPos.z) > 1.0) c = vec3(1.0, 0.0, 0.0);
    
    // Texcoord (go from -0.5..0.5 to 0..1)
    vec2 texCoord = objPos.xz + 0.5;
    
    // Normal
    vec3 ddxWp = dFdx(worldPos);
    vec3 ddyWp = dFdy(worldPos);
    vec3 N = normalize(cross(ddyWp, ddxWp));
    
    vec3 color = toLinear(c);
    
    frag_color = vec4(color, 1.0);
}