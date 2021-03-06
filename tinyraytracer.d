import std.stdio;
import std.algorithm : min, max, swap;
import std.math : sqrt, PI, tan, abs, atan2;
import std.parallelism : parallel;
import std.range : iota;

import ppmreader;

enum width = 1024;
enum height = 768;
enum filename = "./out.ppm";

enum fov = PI / 2.0; // 90
enum far = 1000.0f;
enum depth_limit = 4;
enum envmap_offset = 0;

enum fovtan = tan(fov / 2.0);
enum aspect_ratio = width / cast(float) height;

alias vec3f = float[3];

vec3f normalize(vec3f v)
{
    vec3f w = v[] / sqrt(dotp(v, v));
    return w;
}

vec3f negate(vec3f v)
{
    vec3f r = -v[];
    return r;
}

float dotp(vec3f lhs, vec3f rhs)
{
    float sum = 0;
    foreach (i; 0 .. 3)
        sum += lhs[i] * rhs[i];
    return sum;
}

float norm(vec3f v)
{
    return sqrt(dotp(v, v));
}

class Light
{
    vec3f position;
    float intensity;
    this(vec3f position, float intensity)
    {
        this.position = position;
        this.intensity = intensity;
    }
}

class Material
{
    float refractive_index; // 屈折率
    float[4] albedo; // 反射率
    vec3f diffuse_color;
    float specular_exponent; // 鏡面反射指数
    this(float refractive_index, float[4] albedo, vec3f color, float specular_exponent)
    {
        this.refractive_index = refractive_index;
        this.albedo = albedo;
        this.diffuse_color = color;
        this.specular_exponent = specular_exponent;
    }
}

class Sphere
{
    vec3f center;
    float radius;
    Material material;
    this(vec3f center, float radius, Material material)
    {
        this.center = center;
        this.radius = radius;
        this.material = material;
    }

    bool isIntersectWithTheRay(vec3f orig, vec3f dir, ref float dist)
    {
        vec3f L = this.center[] - orig[];
        float tca = dotp(L, dir);
        float d = dotp(L, L) - tca * tca;
        if (this.radius * this.radius < d)
            return false;
        float thc = sqrt(this.radius * this.radius - d);
        dist = tca - thc;
        if (dist < 0)
            dist = tca + thc;
        if (dist < 0)
            return false;
        return true;
    }
}

// 法線ベクトルに従ってIを反射
vec3f reflect(vec3f I, vec3f normal)
{
    vec3f r = I[] - normal[] * 2.0f * dotp(I, normal);
    return r;
}

vec3f refract(vec3f I, vec3f normal, float refractive_index)
{
    float cosi = -dotp(I, normal).min(1.0).max(-1.0); // cos(入射角)
    float etai = 1.0;
    float etat = refractive_index;
    vec3f N = normal;
    if (cosi < 0)
    {
        cosi = -cosi;
        swap(etai, etat);
        N = N.negate();
    }
    float eta = etai / etat;
    float k = 1 - eta * eta * (1 - cosi * cosi);
    if (k < 0)
    {
        return [0.0, 0.0, 0.0];
    }
    else
    {
        vec3f r = I[] * eta + N[] * (eta * cosi - sqrt(k));
        return r;
    }
}

/**
    hit:        ヒット座標
    normal:     ヒットした面の法線ベクトル
    material:   ヒットした面のマテリアル
*/
bool intersectScene(vec3f orig, vec3f dir, Sphere[] spheres, ref vec3f hit,
        ref vec3f normal, ref Material material)
{
    float spheres_dist = float.max;
    foreach (sphere; spheres)
    {
        float dist_i;
        bool b = sphere.isIntersectWithTheRay(orig, dir, dist_i);
        if (b && dist_i < spheres_dist)
        {
            spheres_dist = dist_i;
            hit = orig[] + dir[] * dist_i;
            normal = hit[] - sphere.center[];
            normal = normalize(normal);
            material = sphere.material;
        }
    }

    float checkerboard_dist = float.max;
    if (1e-3 < abs(dir[1]))
    {
        float d = -(orig[1] + 4) / dir[1];
        vec3f pt = orig[] + dir[] * d;
        if (0 < d && d < spheres_dist)
        {
            checkerboard_dist = d;
            hit = pt;
            normal = [0.0, 1.0, 0.0];
            bool checker = (cast(int)(0.5 * hit[0] + 1000) + cast(int)(0.5 * hit[2])) & 1;
            vec3f diffuse_color = (checker ? [1.0, 1.0, 1.0] : [1.0, 0.7, 0.3]);
            material = new Material(1.0, [1, 0, 0, 0], diffuse_color, 50.0);
            material.diffuse_color[] *= 0.3;
        }
    }

    return min(spheres_dist, checkerboard_dist) < far;
}

vec3f castRay(vec3f orig, vec3f dir, Sphere[] spheres, Light[] lights, Envmap envmap, size_t depth)
{
    vec3f hit, normal;
    Material material;
    if (depth <= depth_limit && intersectScene(orig, dir, spheres, hit, normal, material))
    {
        float diffuse_light_intensity = 0;
        float specular_light_intensity = 0;
        vec3f reflect_color;
        vec3f refract_color;

        {
            vec3f reflect_dir = reflect(dir, normal).normalize();
            vec3f reflect_orig = hit;
            if (dotp(reflect_dir, normal) < 0)
            {
                reflect_orig[] -= normal[] * 1e-3;
            }
            else
            {
                reflect_orig[] += normal[] * 1e-3;
            }
            reflect_color = castRay(reflect_orig, reflect_dir, spheres, lights, envmap, depth + 1);
        }

        {
            vec3f refract_dir = refract(dir, normal, material.refractive_index).normalize();
            vec3f refract_orig = hit;
            if (dotp(refract_dir, normal) < 0)
            {
                refract_orig[] -= normal[] * 1e-3;
            }
            else
            {
                refract_orig[] += normal[] * 1e-3;
            }
            refract_color = castRay(refract_orig, refract_dir, spheres, lights, envmap, depth + 1);
        }

        loop_lights: foreach (light; lights)
        {
            vec3f light_tmp = light.position[] - hit[];
            vec3f light_dir = normalize(light_tmp);

            {
                float light_dist = light_tmp.norm();
                vec3f micro_normal = normal[] * 1e-3;
                // hitの位置から光源に向かってscene_intersectを実行する。
                // 自分と衝突しないように法線ベクトル方向にちょっとずらす
                vec3f shadow_orig = hit;
                if (dotp(light_dir, normal) < 0)
                {
                    shadow_orig[] -= micro_normal[];
                }
                else
                {
                    shadow_orig[] += micro_normal[];
                }
                vec3f shadow_hit, tmp_n;
                Material tmp_m;
                bool is_shadow_falls = intersectScene(shadow_orig, light_dir,
                        spheres, shadow_hit, tmp_n, tmp_m);
                vec3f shadow_dist = shadow_hit[] - shadow_orig[];
                if (is_shadow_falls && shadow_dist.norm() < light_dist)
                    continue loop_lights;
            }

            diffuse_light_intensity += light.intensity * max(0.0, dotp(light_dir, normal));
            float r = max(0.0, dotp(reflect(light_dir.negate(), normal).negate(), dir));
            specular_light_intensity += (r ^^ material.specular_exponent) * light.intensity;
        }
        vec3f a = material.diffuse_color[] * diffuse_light_intensity * material.albedo[0];
        vec3f b = [1.0f, 1.0f, 1.0f] * specular_light_intensity * material.albedo[1];
        vec3f c = reflect_color[] * material.albedo[2];
        vec3f d = refract_color[] * material.albedo[3];
        vec3f r = a[] + b[] + c[] + d[];
        return r;
    }

    float theta = atan2(dir[2], dir[0]);
    float phi = -atan2(dir[1], sqrt(dir[2] ^^ 2 + dir[0] ^^ 2));

    size_t x = cast(size_t)((((theta + PI) / (PI * 2)) * envmap.width).min(envmap.width).max(0));
    size_t y = cast(size_t)((((phi + PI) / (PI * 2)) * envmap.height).min(envmap.height).max(0));

    x = (x + envmap_offset) % envmap.width;

    return envmap.v[y * envmap.width + x];
}

void render(Sphere[] spheres, Light[] lights, Envmap envmap)
{
    auto framebuffer = new vec3f[](width * height);

    foreach (j; iota(height).parallel())
        foreach (i; 0 .. width)
        {
            float x = (2 * (i + 0.5) / cast(float) width - 1) * fovtan * aspect_ratio;
            float y = -(2 * (j + 0.5) / cast(float) height - 1) * fovtan;
            vec3f dir = [x, y, -1].normalize;
            framebuffer[i + j * width] = castRay([0, 0, 0], dir, spheres, lights, envmap, 0);
        }

    auto ofile = File(filename, "w"); // write
    ofile.writeln("P6");
    ofile.writeln(width, " ", height);
    ofile.writeln(255);

    foreach (i; 0 .. width * height)
    {
        vec3f c = framebuffer[i];
        float max = c[0].max(c[1]).max(c[2]);
        if (1 < max)
        {
            framebuffer[i][] *= (1 / max);
        }
        foreach (j; 0 .. 3)
            ofile.write(cast(char)(255 * framebuffer[i][j].min(1.0).max(0.0)));
    }

    ofile.close();
}

void main()
{
    Material ivory = new Material(1.0, [0.6, 0.3, 0.1, 0.0], [0.4, 0.4, 0.3], 50.0);
    Material glass = new Material(1.5, [0.0, 0.5, 0.1, 0.8], [0.6, 0.7, 0.8], 125.0);
    Material red_rubber = new Material(1.0, [0.9, 0.1, 0.0, 0.0], [0.3, 0.1, 0.1], 10.0);
    Material mirror = new Material(1.0, [0.0, 10.0, 0.8, 0.0], [1.0, 1.0, 1.0], 1425);

    Sphere[] spheres;
    spheres ~= new Sphere([-3.0, 0.0, -16.0], 2.0, ivory);
    spheres ~= new Sphere([-1.0, -1.5, -12.0], 2.0, glass);
    spheres ~= new Sphere([1.5, -0.5, -18.0], 3.0, red_rubber);
    spheres ~= new Sphere([7.0, 5.0, -18.0], 4.0, mirror);

    Light[] lights;
    lights ~= new Light([-20, 20, 20], 1.5);
    lights ~= new Light([30, 50, -25], 1.8);
    lights ~= new Light([30, 20, 30], 1.7);

    Envmap envmap = new Envmap("envmap.ppm");

    render(spheres, lights, envmap);
}
