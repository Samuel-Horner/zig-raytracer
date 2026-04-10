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

int divFloor(int num, int denum) {
    return int(floor(float(num) / float(denum)));
}

uint udivFloor(uint num, uint denum) {
    return uint(floor(float(num) / float(denum)));
}

ivec3 ivec3Floor(vec3 v) {
    return ivec3(floor(v));
}

#define empty 0

#define divisions 2
#define child_count divisions * divisions * divisions

struct MetaData {
    ivec3 pos;
    uint size;
};

#define meta_data_size 4
#define node_size 2

MetaData getMetaData() {
    return MetaData(
        ivec3(int(tree[0]), int(tree[1]), int(tree[2])),
        tree[3]
    );
}

MetaData meta_data = getMetaData();

uint getIndex(ivec3 pos) {
    return pos.x * divisions * divisions + pos.y * divisions + pos.z;
}

ivec3 getRelativePos(uint index) {
    return ivec3(
        index / (divisions * divisions),
        (index % (divisions * divisions)) / divisions,
        index % divisions
    );
}

ivec3 getRelativeNodePos(ivec3 abs_pos, uint size, ivec3 voxel_pos) {
    float division_size = float(size) / divisions;
    vec3 node_space_pos = vec3(voxel_pos - abs_pos);

    return ivec3Floor(node_space_pos / division_size);
}

ivec3 getPos(ivec3 parent_pos, uint index) {
    return parent_pos + getRelativePos(index);
}

uint getNodePtr(uint index, uint children_ptr) {
    return tree[children_ptr + index];
}

// Returns uvec2(voxel, size)
uvec2 getVoxel(ivec3 pos) {
    uint size = meta_data.size;
    ivec3 node_pos = meta_data.pos;
    uint node_ptr = meta_data_size;

    while (size > divisions) {
        uint children_ptr = node_ptr + node_size;
        ivec3 relative_pos = getRelativeNodePos(node_pos, size, pos);
        node_ptr = getNodePtr(getIndex(relative_pos), children_ptr);

        if (node_ptr == 0) return uvec2(empty, size);

        size = udivFloor(size, divisions);
        node_pos = node_pos + relative_pos * int(size);
    }

    uint children_ptr = node_ptr + node_size;
    ivec3 relative_pos = getRelativeNodePos(node_pos, size, pos);

    return uvec2(tree[children_ptr + getIndex(relative_pos)], 1);
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

    return vec2(max(tnear, 0), tfar);
    // if (tfar - tnear > 0) {
    //     return vec2(tnear, tfar);
    // } else {
    //     return vec2(-1.);
    // }
}

#define MAX_32 0xFFFFFF
#define MAX_TRAVERSAL_DEPTH 256
#define OFFSET 0.0001

uint hitTree(Ray ray) {
    uint hit_count = 0;

    vec2 hit_tree = hitAABB(ray, vec3(meta_data.pos), float(meta_data.size));

    if (hit_tree.y - hit_tree.x <= 0) { return empty; }

    float next = hit_tree.x;
    float max = hit_tree.y;

    for (uint i = 0; i < MAX_TRAVERSAL_DEPTH; i++) {
        ivec3 voxel_pos = ivec3Floor(at(ray, next + OFFSET));
        uvec2 voxel = getVoxel(voxel_pos);

        if (voxel.x != empty) {
            return voxel.x;
        }

        vec2 hit = hitAABB(ray, vec3(voxel_pos), float(1));
        next = hit.y;

        if (next + OFFSET >= max) {
            break;
        }
    }

    return empty;
}

vec4 rayColor(Ray ray) {
    uint voxel = hitTree(ray);
    if (voxel != empty) {
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
