#define _POSIX_C_SOURCE 200809L
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile sig_atomic_t running = 1;
static void stop(int signal_number) { (void)signal_number; running = 0; }
static double now(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
}
static int number(const char *text, int maximum) {
    char *end;
    errno = 0;
    long value = strtol(text, &end, 10);
    return errno || *end || value < 1 || value > maximum ? -1 : (int)value;
}
static GLuint shader(GLenum type, const char *source) {
    GLuint result = glCreateShader(type);
    glShaderSource(result, 1, &source, NULL);
    glCompileShader(result);
    GLint success;
    glGetShaderiv(result, GL_COMPILE_STATUS, &success);
    if (!success) {
        char log[1024];
        glGetShaderInfoLog(result, sizeof(log), NULL, log);
        fprintf(stderr, "GPU shader compilation failed: %s\n", log);
        glDeleteShader(result);
        return 0;
    }
    return result;
}

int main(int argc, char **argv) {
    if (argc != 6) {
        fprintf(stderr, "Usage: %s phase_seconds slow_fps fast_fps width height\n", argv[0]);
        return 2;
    }
    int phase = number(argv[1], 3600), slow = number(argv[2], 2000);
    int fast = number(argv[3], 2000), width = number(argv[4], 8192), height = number(argv[5], 8192);
    if (phase < 0 || slow < 0 || fast < 0 || width < 0 || height < 0) {
        fprintf(stderr, "GPU load arguments are outside supported positive ranges.\n");
        return 2;
    }
    PFNEGLQUERYDEVICESEXTPROC query = (PFNEGLQUERYDEVICESEXTPROC)eglGetProcAddress("eglQueryDevicesEXT");
    PFNEGLGETPLATFORMDISPLAYEXTPROC platform = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDeviceEXT devices[16];
    EGLint count = 0;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    const EGLint attributes[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE };
    const EGLint size[] = { EGL_WIDTH, width, EGL_HEIGHT, height, EGL_NONE };
    const EGLint version[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    if (query && platform && query(16, devices, &count)) {
        for (int index = 0; index < count; index++) {
            display = platform(EGL_PLATFORM_DEVICE_EXT, devices[index], NULL);
            EGLConfig config;
            EGLint configs;
            if (!eglInitialize(display, NULL, NULL) || !eglBindAPI(EGL_OPENGL_ES_API) ||
                !eglChooseConfig(display, attributes, &config, 1, &configs) || !configs) {
                eglTerminate(display);
                display = EGL_NO_DISPLAY;
                continue;
            }
            context = eglCreateContext(display, config, EGL_NO_CONTEXT, version);
            surface = eglCreatePbufferSurface(display, config, size);
            if (context != EGL_NO_CONTEXT && surface != EGL_NO_SURFACE &&
                eglMakeCurrent(display, surface, surface, context)) {
                const char *vendor = (const char *)glGetString(GL_VENDOR);
                if (vendor && strstr(vendor, "NVIDIA")) break;
            }
            if (surface != EGL_NO_SURFACE) eglDestroySurface(display, surface);
            if (context != EGL_NO_CONTEXT) eglDestroyContext(display, context);
            eglTerminate(display);
            display = EGL_NO_DISPLAY;
        }
    }
    if (display == EGL_NO_DISPLAY) {
        fprintf(stderr, "No NVIDIA EGL rendering device; software rendering is not a profiling substitute.\n");
        return 1;
    }
    printf("GPU fixture: %s, %dx%d, alternating %d/%d fps\n", glGetString(GL_RENDERER), width, height, slow, fast);
    fflush(stdout);
    GLuint vertex = shader(GL_VERTEX_SHADER,
        "attribute vec2 position; varying vec2 uv; void main() {"
        "uv=position*0.5+0.5; gl_Position=vec4(position,0.0,1.0); }");
    GLuint fragment = shader(GL_FRAGMENT_SHADER,
        "precision mediump float; varying vec2 uv; uniform float tick;"
        "void main() { float a=sin(uv.x*32.0+tick)*cos(uv.y*32.0-tick);"
        "gl_FragColor=vec4(uv.x,uv.y,a*0.5+0.5,1.0); }");
    if (!vertex || !fragment) return 1;
    GLuint program = glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glBindAttribLocation(program, 0, "position");
    glLinkProgram(program);
    GLint linked;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (!linked) { fprintf(stderr, "GPU program linking failed.\n"); return 1; }
    glUseProgram(program);
    GLint tick = glGetUniformLocation(program, "tick");
    const GLfloat vertices[] = {-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1};
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, vertices);
    glEnableVertexAttribArray(0);
    glViewport(0, 0, width, height);
    signal(SIGTERM, stop);
    signal(SIGINT, stop);
    double start = now(), next = start, last = start;
    unsigned long frames = 0, phase_frames = 0;
    int previous = -1;
    while (running) {
        double time = now();
        int current = (int)((time - start) / phase) % 2;
        int fps = current ? fast : slow;
        if (current != previous) {
            if (previous >= 0) printf("GPU phase: %lu frames in %.3f seconds\n", phase_frames, time - last);
            printf("GPU target: %d fps\n", fps);
            fflush(stdout);
            previous = current; last = time; phase_frames = 0; next = time;
        }
        glUniform1f(tick, (GLfloat)(frames % 4096) / 120.0f);
        glDrawArrays(GL_TRIANGLES, 0, 6);
        glFinish();
        if (glGetError() != GL_NO_ERROR) { fprintf(stderr, "GPU rendering failed.\n"); return 1; }
        frames++; phase_frames++;
        next += 1.0 / fps;
        if (next < now()) next = now();
        struct timespec deadline = { (time_t)next, (long)((next - (time_t)next) * 1e9) };
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &deadline, NULL);
    }
    printf("GPU fixture stopped after %lu frames.\n", frames);
    glDeleteProgram(program);
    glDeleteShader(vertex); glDeleteShader(fragment);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, surface); eglDestroyContext(display, context);
    eglTerminate(display);
    return 0;
}
