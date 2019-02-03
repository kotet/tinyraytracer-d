import std.stdio;
import std.algorithm : min, max;
import std.math : sqrt, PI, tan;

enum width = 1024;
enum height = 768;
enum filename = "./out.ppm";

enum fov = PI / 2.0; // 90
enum far = 1000.0f;

enum fovtan = tan(fov / 2.0);
enum aspect_ratio = width / cast(float) height;

alias vec3f = float[3];

vec3f normalize(vec3f v)
{
    vec3f w = v[] / sqrt(dotp(v, v));
    return w;
}

float dotp(vec3f lhs, vec3f rhs)
{
    float sum = 0;
    foreach (i; 0 .. 3)
        sum += lhs[i] * rhs[i];
    return sum;
}

class Material
{
    vec3f diffuse_color;
    this(vec3f color)
    {
        this.diffuse_color = color;
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
            normal.normalize();
            material = sphere.material;
        }
    }
    return spheres_dist < far;
}

vec3f castRay(vec3f orig, vec3f dir, Sphere[] spheres)
{
    vec3f hit, normal;
    Material material;
    if (intersectScene(orig, dir, spheres, hit, normal, material))
        return material.diffuse_color;
    return [0.2, 0.7, 0.8];
}

void render(Sphere[] spheres)
{
    auto framebuffer = new vec3f[](width * height);

    foreach (j; 0 .. height)
        foreach (i; 0 .. width)
        {
            float x = (2 * (i + 0.5) / cast(float) width - 1) * fovtan * aspect_ratio;
            float y = -(2 * (j + 0.5) / cast(float) height - 1) * fovtan;
            vec3f dir = [x, y, -1].normalize;
            framebuffer[i + j * width] = castRay([0, 0, 0], dir, spheres);
        }

    auto ofile = File(filename, "w"); // write
    ofile.writeln("P6");
    ofile.writeln(width, " ", height);
    ofile.writeln(255);

    foreach (i; 0 .. width * height)
        foreach (j; 0 .. 3)
            ofile.write(cast(char)(255 * framebuffer[i][j].min(1.0).max(0.0)));

    ofile.close();
}

void main()
{
    Material ivory = new Material([0.4, 0.4, 0.3]);
    Material red_rubber = new Material([0.3, 0.1, 0.1]);

    Sphere[] spheres;
    spheres ~= new Sphere([-3.0, 0.0, -16.0], 2.0, ivory);
    spheres ~= new Sphere([-1.0, -1.5, -12.0], 2.0, red_rubber);
    spheres ~= new Sphere([1.5, -0.5, -18.0], 3.0, red_rubber);
    spheres ~= new Sphere([7.0, 5.0, -18.0], 4.0, ivory);

    render(spheres);
}
