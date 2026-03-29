#version 460 core

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D imgOutput;

layout(std430, binding = 0) readonly buffer TreeSSBO {
    uint tree[];
};

float distanceSquared(vec3 a, vec3 b) {
    vec3 temp = a - b;
    return dot(a, b);
}

ivec3 uvec3_ivec3(uvec3 x) {
    return ivec3(int(x.x), int(x.y), int(x.z));
}
uvec3 ivec3_uvec3(ivec3 x) {
    return uvec3(uint(x.x), uint(x.y), uint(x.z));
}

#define divisions 2
#define child_count divisions * divisions * divisions

struct MetaData {
    ivec3 pos;
    uint size;
};

#define meta_data_size 4
#define node_size 1

MetaData getMetaData() {
    return MetaData(
        ivec3(int(tree[0]), int(tree[1]), int(tree[2])),
        tree[3]
    );
}

MetaData meta_data = getMetaData();

uint getIndex(uvec3 pos) {
    return pos.x * divisions * divisions + pos.y * divisions + pos.z;
}

uvec3 getRelativePos(uint index) {
    return uvec3(
        index / (divisions * divisions),
        (index % (divisions * divisions)) / divisions,
        index % divisions
    );
}

uvec3 getPos(ivec3 parent_pos, uint index) {
    return uvec3(uint(parent_pos.x), uint(parent_pos.y), uint(parent_pos.z)) + getRelativePos(index);
}

uint getVoxel(ivec3 pos) {
    return 0;
}

uniform vec3 cam_pos;
uniform vec3 cam_pixel00_loc;
uniform vec3 cam_pixel_delta_u;
uniform vec3 cam_pixel_delta_v;

// https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-box-intersection.html
struct Ray {
    vec3 origin;
    vec3 dir;
    vec3 invdir;
};

Ray initRay(vec3 origin, vec3 dir) {
    return Ray(origin, dir, vec3(1.) / dir);
}

vec3 at(Ray ray, float t) {
    return ray.origin + t * ray.dir;
}

// https://gist.github.com/DomNomNom/46bb1ce47f68d255fd5d
// compute the near and far intersections of the cube (stored in the x and y components) using the slab method
// no intersection means vec.x > vec.y (really tNear > tFar)
vec2 hitAABB(Ray ray, vec3 vmin, float size) {
    vec3 vmax = vmin + vec3(size);
    vec3 tmin = (vmin - ray.origin) * ray.invdir;
    vec3 tmax = (vmax - ray.origin) * ray.invdir;
    vec3 t1 = min(tmin, tmax);
    vec3 t2 = max(tmin, tmax);
    float tnear = max(max(t1.x, t1.y), t1.z);
    float tfar = min(min(t2.x, t2.y), t2.z);

    if (tnear > 0 && tfar - tnear > 0) {
        return vec2(tnear, tfar);
    } else {
        return vec2(-1.);
    }
}

#define MAX_32 0xFFFFFF

uint findClosestIntersectionIndex(Ray ray, ivec3 parent_pos, uint size, uint children_ptr) {
    uint division_size = size / divisions;
    vec2 hit_dists[child_count];

    for (uint i = 0; i < child_count; i++) {
        uvec3 relative_pos = getRelativePos(i);
        ivec3 node_pos = parent_pos + uvec3_ivec3(relative_pos * division_size);

        hit_dists[i] = hitAABB(ray, node_pos, division_size);
    }

    // Return minimum distance index
    uint index = 0;
    float min_dist = -1;

    for (uint i = 0; i < divisions * divisions * divisions; i++) {
        float dist = hit_dists[i].x;
        if (dist < 0) continue;

        if ((min_dist < 0 || dist < min_dist) && (tree[children_ptr + i] != 0)) {
            min_dist = dist;
            index = i;
        }
    }

    if (min_dist == -1) return MAX_32;

    return index;
}

#define MAX_TRAVERSAL_DEPTH 256

uint hitTree(Ray ray) {
    if (hitAABB(ray, vec3(meta_data.pos), float(meta_data.size)).x > 0) {
        return MAX_32;
    }

    return 0;
}

vec4 rayColor(Ray ray) {
    uint voxel = hitTree(ray);
    if (voxel != 0) {
        const vec3 col = vec3(
                (voxel) & uint(0xFF),
                (voxel >> 8) & uint(0xFF),
                (voxel >> 16) & uint(0xFF)
            );

        return vec4(col / 256., 1.);
    }

    vec3 unit_direction = normalize(ray.dir);
    return vec4(unit_direction, 1.);
}

void main() {
    vec4 value = vec4(0.0, 0.0, 0.0, 1.0);
    ivec2 texelCoord = ivec2(gl_GlobalInvocationID.xy);

    vec3 pixel_center = cam_pixel00_loc + (texelCoord.x * cam_pixel_delta_u) + (texelCoord.y * cam_pixel_delta_v);
    Ray ray = initRay(cam_pos, pixel_center - cam_pos);

    vec4 col = rayColor(ray);

    imageStore(imgOutput, texelCoord, col);
}
