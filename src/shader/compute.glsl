#version 460 core

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D imgOutput;

uniform vec3 cam_pos;
uniform vec3 cam_pixel00_loc;
uniform vec3 cam_pixel_delta_u;
uniform vec3 cam_pixel_delta_v;

struct Ray {
    vec3 origin;
    vec3 dir;
};

vec3 at(Ray ray, float t) {
    return ray.origin + t * ray.dir;
}

float hitSphere(Ray ray, vec3 center, float radius) {
    vec3 oc = center - ray.origin;
    float a = dot(ray.dir, ray.dir);
    float b = -2.0 * dot(ray.dir, oc);
    float c = dot(oc, oc) - radius * radius;
    float discriminant = b * b - 4 * a * c;
    if (discriminant < 0) {
        return -1.;
    } else {
        return (-b - sqrt(discriminant) ) / (2.*a);
    }
}

vec4 rayColor(Ray ray) {
    float t = hitSphere(ray, vec3(0,0,-1), 0.5);
    if (t > 0.) {
        vec3 N = normalize(at(ray, t) - vec3(0,0,-1));
        return vec4(0.5*vec3(N.x+1, N.y+1, N.z+1), 1.);
    }

    vec3 unit_direction = normalize(ray.dir);
    return vec4(unit_direction, 1.);
}

void main() {
    vec4 value = vec4(0.0, 0.0, 0.0, 1.0);
    ivec2 texelCoord = ivec2(gl_GlobalInvocationID.xy);

    vec3 pixel_center = cam_pixel00_loc + (texelCoord.x * cam_pixel_delta_u) + (texelCoord.y * cam_pixel_delta_v);
    Ray ray = Ray(cam_pos, pixel_center - cam_pos);

    vec4 col = rayColor(ray);

    imageStore(imgOutput, texelCoord, col);
}
