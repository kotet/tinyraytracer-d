import std.stdio;
import std.algorithm : min, max;
import std.math : sqrt, PI, tan;

enum width = 1024;
enum height = 768;
enum filename = "./out.ppm";

enum fov = PI / 2.0; // 90
enum fovtan = tan(fov / 2.0);
enum aspect_ratio = width / cast(float) height;

alias vec3f = float[3];

vec3f normalize(vec3f v)
{
    vec3f w = v[] / sqrt(dotp(v,v));
    return w;
}

float dotp(vec3f lhs, vec3f rhs)
{
    float sum = 0;
    foreach (i; 0 .. 3)
        sum += lhs[i] * rhs[i];
    return sum;
}

class Sphere
{
    vec3f center;
    float radius;
    this(vec3f center, float radius)
    {
        this.center = center;
        this.radius = radius;
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

vec3f castRay(vec3f orig, vec3f dir, Sphere sphere)
{
    float sphere_dist = float.max;
    if (sphere.isIntersectWithTheRay(orig, dir, sphere_dist))
        return [0.4, 0.4, 0.3];
    return [0.2, 0.7, 0.8];
}

void render(Sphere sphere)
{
    auto framebuffer = new vec3f[](width * height);

    foreach (j; 0 .. height)
        foreach (i; 0 .. width)
        {
            float x = (2 * (i + 0.5) / cast(float) width - 1) * fovtan * aspect_ratio;
            float y = -(2 * (j + 0.5) / cast(float) height - 1) * fovtan;
            vec3f dir = [x, y, -1].normalize;
            framebuffer[i + j * width] = castRay([0, 0, 0], dir, sphere);
        }

    auto ofile = File(filename, "w"); // write, binary
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
    auto sphere = new Sphere([-3.0, 0.0, -16.0], 2.0);
    render(sphere);
}
