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

#define divisions 2
#define child_count divisions * divisions * divisions

// https://www.geeksforgeeks.org/c/quick-sort-in-c/
void swap(inout float a, inout float b) {
    float t = a;
    a = b;
    b = a;
}

uint part(inout float arr[child_count], uint low, uint high) {
    float p = arr[low];
    uint i = low;
    uint j = high;

    while (i < j) {
        while (arr[i] <= p && i < j) i++;
        while (arr[j] > p && j > i) j++;

        if (i < j) swap(arr[i], arr[j]);
    }

    swap(arr[low], arr[high]);
    return j;
}

void sort(inout float arr[child_count], uint low, uint high) {
    if (low < high) {
        uint pi = part(arr, low, high);

        sort(arr, low, pi - 1);
        sort(arr, pi + 1, high);
    }
}

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

struct StackItem {
    uint node_ptr;
    float t;
};

#define MAX_TRAVERSAL_STACK_SIZE 4096
struct Stack {
    StackItem items;
    uint top;
};

void stackPush(in Stack stack, StackEntry item) {
    stack.items[stack.top++] = item;
}

StackItem stackPop(in Stack stack) {
    return stack.items[--stack.top];
}

// https://gist.github.com/DomNomNom/46bb1ce47f68d255fd5d
// compute the near and far intersections of the cube (stored in the x and y components) using the slab method
// no intersection means vec.x > vec.y (really tNear > tFar)
float hitAABB(Ray ray, vec3 vmin, float size) {
    vec3 vmax = vmin + vec3(size);
    vec3 tmin = (vmin - ray.origin) * ray.invdir;
    vec3 tmax = (vmax - ray.origin) * ray.invdir;
    vec3 t1 = min(tmin, tmax);
    vec3 t2 = max(tmin, tmax);
    float tnear = max(max(t1.x, t1.y), t1.z);
    float tfar = min(min(t2.x, t2.y), t2.z);

    if (tnear >= 0 && tnear <= tfar) {
        return tnear;
    } else {
        return -1;
    }
}

#define INVALID_INDEX 0xFFFFFF

uint findClosestIntersectionIndex(Ray ray, ivec3 parent_pos, uint size, uint children_ptr) {
    uint division_size = size / divisions;
    float hit_dists[child_count];

    for (uint i = 0; i < child_count; i++) {
        uvec3 relative_pos = getRelativePos(i);
        ivec3 node_pos = parent_pos + uvec3_ivec3(relative_pos * division_size);

        hit_dists[i] = hitAABB(ray, node_pos, division_size);
    }

    sort(hit_dists, 0, child_count - 1);

    // Return minimum distance index
    uint index = 0;
    float min_dist = -1;

    for (uint i = 0; i < divisions * divisions * divisions; i++) {
        float dist = hit_dists[i];
        if (dist < 0) continue;

        if ((min_dist < 0 || dist < min_dist) && (tree[children_ptr + i] != 0)) {
            min_dist = dist;
            index = i;
        }
    }

    if (min_dist == -1) return INVALID_INDEX;

    return index;
}

uint hitTree(Ray ray) {
    if (hitAABB(ray, vec3(meta_data.pos), meta_data.size) < 0) return 0;

    uint size = meta_data.size;
    ivec3 node_pos = meta_data.pos;
    uint node_ptr = meta_data_size;
    uint parent_ptr = 0;

    while (size > 2) {
        uint children_ptr = node_ptr + node_size;
        uint hit_index = findClosestIntersectionIndex(ray, node_pos, size, children_ptr);
        node_ptr = tree[children_ptr + hit_index];

        if (hit_index == INVALID_INDEX) return 0;

        if (node_ptr == 0) return 0;

        size = size / divisions;
        node_pos = node_pos + (uvec3_ivec3(getRelativePos(hit_index) * size));
    }

    uint children_ptr = node_ptr + node_size;
    uint hit_index = findClosestIntersectionIndex(ray, node_pos, size, children_ptr);

    if (hit_index == INVALID_INDEX) return 0;

    return tree[children_ptr + hit_index];
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
