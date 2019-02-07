module ppmreader;

import std.stdio;
import std.string : chomp;
import std.array : split;
import std.conv : to;

alias vec3f = float[3];

class Envmap
{
    vec3f[] v;
    size_t width, height;
    this(string filename)
    {
        auto file = File(filename, "r");
        file.readln(); // P6
        file.readln(); // comment
        
        auto wh = file.readln().chomp().split(' ').to!(size_t[]);
        this.width = wh[0];
        this.height = wh[1];
        v = new vec3f[](width * width);
        v[] = [0.5, 0.5, 0.5];
        size_t x = file.readln().chomp().to!size_t;

        auto buf = new ubyte[](width * height * 3);
        file.rawRead(buf);
        size_t j = 0;
        foreach (i; ((width - height) / 2) * width .. (((width - height) / 2) * width
                + width * height))
        {
            v[i][0] = buf[j++] / cast(float) x;
            v[i][1] = buf[j++] / cast(float) x;
            v[i][2] = buf[j++] / cast(float) x;
        }
        this.height = this.width;
    }
}
