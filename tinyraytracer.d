import std.stdio;
import std.algorithm : min, max;

enum width = 1024;
enum height = 768;
enum filename = "./out.ppm";

alias vec3f = float[3];

void render()
{
    auto framebuffer = new vec3f[](width * height);
    foreach (y; 0 .. height)
        foreach (x; 0 .. width)
            framebuffer[x + y * width] = [y / cast(float)(height), x / cast(float)(height), 0];

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
    render();
}
