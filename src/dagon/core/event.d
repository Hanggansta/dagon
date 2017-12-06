/*
Copyright (c) 2014-2017 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.core.event;

import std.stdio;
import std.ascii;
import derelict.sdl2.sdl;
import dlib.core.memory;
import dagon.core.ownership;

enum EventType
{
    KeyDown,
    KeyUp,
    TextInput,
    MouseMotion,
    MouseButtonDown,
    MouseButtonUp,
    MouseWheel,
    JoystickButtonDown,
    JoystickButtonUp,
    JoystickAxisMotion,
    Resize,
    FocusLoss,
    FocusGain,
    Quit,
    UserEvent
}

struct Event
{
    EventType type;
    int key;
    dchar unicode;
    int button;
    int joystickButton;
    int joystickAxis;
    float joystickAxisValue;
    int width;
    int height;
    int userCode;
    int mouseWheelX;
    int mouseWheelY;
}

class EventManager
{
    SDL_Window* window;

    enum maxNumEvents = 50;
    Event[maxNumEvents] eventStack;
    Event[maxNumEvents] userEventStack;
    uint numEvents;
    uint numUserEvents;

    bool running = true;

    bool[512] keyPressed = false;
    bool[255] mouseButtonPressed = false;
    int mouseX = 0;
    int mouseY = 0;
    int mouseRelX = 0;
    int mouseRelY = 0;
    bool enableKeyRepeat = false;

    double deltaTime = 0.0;
    double averageDelta = 0.0;
    uint deltaTimeMs = 0;
    int fps = 0;

    //uint videoWidth;
    //uint videoHeight;

    uint windowWidth;
    uint windowHeight;
    bool windowFocused = true;
    
    SDL_GameController* controller;

    this(SDL_Window* win, uint winWidth, uint winHeight)
    {
        window = win;

        windowWidth = winWidth;
        windowHeight = winHeight;

        //auto videoInfo = SDL_GetVideoInfo();
        //videoWidth = videoInfo.current_w;
        //videoHeight = videoInfo.current_h;

        if (SDL_IsGameController(0))
        {
            writeln("Game controller found!");
            controller = SDL_GameControllerOpen(0);
            
            SDL_Joystick* joy = SDL_GameControllerGetJoystick(controller);
            int instanceID = SDL_JoystickInstanceID(joy);
            
            SDL_GameControllerAddMappingsFromFile("gamecontrollerdb.txt");
            
            if (SDL_GameControllerMapping(controller) is null)
                writeln("Warning: no mapping found for controller!");
            
            SDL_GameControllerEventState(SDL_ENABLE);
        }
    }

    void addEvent(Event e)
    {
        if (numEvents < maxNumEvents)
        {
            eventStack[numEvents] = e;
            numEvents++;
        }
        else
            writeln("Warning: event stack overflow");
    }

    void addUserEvent(Event e)
    {
        if (numUserEvents < maxNumEvents)
        {
            userEventStack[numUserEvents] = e;
            numUserEvents++;
        }
        else
            writeln("Warning: user event stack overflow");
    }

    void generateUserEvent(int code)
    {
        Event e = Event(EventType.UserEvent);
        e.userCode = code;
        addUserEvent(e);
    }
    
    float joystickAxis(int axis)
    {
        return cast(float)(SDL_GameControllerGetAxis(controller, cast(SDL_GameControllerAxis) axis)) / 32_768.0f;
    }

    void update()
    {
        numEvents = 0;
        updateTimer();
        
        mouseRelX = 0;
        mouseRelY = 0;

        for (uint i = 0; i < numUserEvents; i++)
        {
            Event e = userEventStack[i];
            addEvent(e);
        }

        numUserEvents = 0;

        SDL_Event event;

        while(SDL_PollEvent(&event))
        {
            Event e;
            switch (event.type)
            {
                case SDL_KEYDOWN:
                    if (event.key.repeat && !enableKeyRepeat)
                        break;
                    if ((event.key.keysym.unicode & 0xFF80) == 0)
                    {
                        auto asciiChar = event.key.keysym.unicode & 0x7F;
                        if (isPrintable(asciiChar))
                        {
                            e = Event(EventType.TextInput);
                            e.unicode = asciiChar;
                            addEvent(e);
                        }
                    }
                    else
                    {
                        e = Event(EventType.TextInput);
                        e.unicode = event.key.keysym.unicode;
                        addEvent(e);
                    }

                    keyPressed[event.key.keysym.scancode] = true;
                    e = Event(EventType.KeyDown);
                    e.key = event.key.keysym.scancode;
                    addEvent(e);
                    break;

                case SDL_KEYUP:
                    keyPressed[event.key.keysym.scancode] = false;
                    e = Event(EventType.KeyUp);
                    e.key = event.key.keysym.scancode;
                    addEvent(e);
                    break;

                case SDL_MOUSEMOTION:
                    mouseX = event.motion.x;
                    mouseY = event.motion.y;
                    mouseRelX = event.motion.xrel;
                    mouseRelY = event.motion.yrel;
                    break;

                case SDL_MOUSEBUTTONDOWN:
                    mouseButtonPressed[event.button.button] = true;
                    e = Event(EventType.MouseButtonDown);
                    e.button = event.button.button;
                    addEvent(e);
                    break;

                case SDL_MOUSEBUTTONUP:
                    mouseButtonPressed[event.button.button] = false;
                    e = Event(EventType.MouseButtonUp);
                    e.button = event.button.button;
                    addEvent(e);
                    break;
                    
                case SDL_MOUSEWHEEL:
                    e = Event(EventType.MouseWheel);
                    e.mouseWheelX = event.wheel.x;
                    e.mouseWheelY = event.wheel.y;
                    addEvent(e);
                    break;

                case SDL_CONTROLLERBUTTONDOWN:
                    // TODO: add state modification
                    if (event.cbutton.state == SDL_PRESSED)
                        e = Event(EventType.JoystickButtonDown);
                    else if (event.cbutton.state == SDL_RELEASED)
                        e = Event(EventType.JoystickButtonUp);
                    e.joystickButton = event.cbutton.button;
                    addEvent(e);
                    break;

                case SDL_CONTROLLERBUTTONUP: 
                    // TODO: add state modification
                    if (event.cbutton.state == SDL_PRESSED)
                        e = Event(EventType.JoystickButtonDown);
                    else if (event.cbutton.state == SDL_RELEASED)
                        e = Event(EventType.JoystickButtonUp);
                    e.joystickButton = event.cbutton.button;
                    addEvent(e);
                    break;

                case SDL_CONTROLLERAXISMOTION:
                    // TODO: add state modification
                    e = Event(EventType.JoystickAxisMotion);
                    e.joystickAxis = event.caxis.axis;
                    e.joystickAxisValue = cast(float)event.caxis.value / 32768.0f;
                    
                    if (controller)
                    {
                        if (e.joystickAxis == 0)
                            e.joystickAxisValue = SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTY);
                        if (e.joystickAxis == 1)
                            e.joystickAxisValue = SDL_GameControllerGetAxis(controller, SDL_CONTROLLER_AXIS_LEFTX);
                            
                        e.joystickAxisValue = e.joystickAxisValue / 32768.0f; 
                    }
                    
                    addEvent(e);
                    break;

                //case SDL_WINDOWEVENT_RESIZED:
                case SDL_WINDOWEVENT:
                    if (event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED)
                    {
                        windowWidth = event.window.data1;
                        windowHeight = event.window.data2;
                        e = Event(EventType.Resize);
                        e.width = windowWidth;
                        e.height = windowHeight;
                        addEvent(e);
                    }
                    break;
/*
                case SDL_ACTIVEEVENT:
                    if (event.active.state & SDL_APPACTIVE)
                    {
                        if (event.active.gain == 0)
                        {
                            writeln("Deactivated");
                            windowFocused = false;
                            e = Event(EventType.FocusLoss);
                        }
                        else
                        {
                            writeln("Activated");
                            windowFocused = true;
                            e = Event(EventType.FocusGain);
                        }
                    }
                    else if (event.active.state & SDL_APPINPUTFOCUS)
                    {
                        if (event.active.gain == 0)
                        {
                            writeln("Lost focus");
                            windowFocused = false;
                            e = Event(EventType.FocusLoss);
                        }
                        else
                        {
                            writeln("Gained focus");
                            windowFocused = true;
                            e = Event(EventType.FocusGain);
                        }
                    }
                    addEvent(e);
                    break;
*/
                case SDL_QUIT:
                    running = false;
                    e = Event(EventType.Quit);
                    addEvent(e);
                    break;

                default:
                    break;
            }
        }
    }

    void updateTimer()
    {
        static int currentTime;
        static int lastTime;

        static int FPSTickCounter;
        static int FPSCounter = 0;

        currentTime = SDL_GetTicks();
        auto elapsedTime = currentTime - lastTime;
        lastTime = currentTime;
        deltaTimeMs = elapsedTime;
        deltaTime = cast(double)(elapsedTime) * 0.001;

        FPSTickCounter += elapsedTime;
        FPSCounter++;
        if (FPSTickCounter >= 1000) // 1 sec interval
        {
            fps = FPSCounter;
            FPSCounter = 0;
            FPSTickCounter = 0;
            averageDelta = 1.0 / cast(double)(fps);
        }
    }

    void setMouse(int x, int y)
    {
        SDL_WarpMouseInWindow(window, x, y);
        mouseX = x;
        mouseY = y;
    }

    void setMouseToCenter()
    {
        float x = (cast(float)windowWidth)/2;
        float y = (cast(float)windowHeight)/2;
        setMouse(cast(int)x, cast(int)y);
    }

    void showCursor(bool mode)
    {
        SDL_ShowCursor(mode);
    }
    
    float aspectRatio()
    {
        return cast(float)windowWidth / cast(float)windowHeight;
    }
}

abstract class EventListener: Owner
{
    EventManager eventManager;
    bool enabled = true;

    this(EventManager emngr, Owner owner)
    {
        super(owner);
        eventManager = emngr;
    }

    protected void generateUserEvent(int code)
    {
        eventManager.generateUserEvent(code);
    }

    void processEvents()
    {
        if (!enabled)
            return;

        for (uint i = 0; i < eventManager.numEvents; i++)
        {
            Event* e = &eventManager.eventStack[i];
            processEvent(e);
        }
    }

    void processEvent(Event* e)
    {
        switch(e.type)
        {
            case EventType.KeyDown:
                onKeyDown(e.key);
                break;
            case EventType.KeyUp:
                onKeyUp(e.key);
                break;
            case EventType.TextInput:
                onTextInput(e.unicode);
                break;
            case EventType.MouseButtonDown:
                onMouseButtonDown(e.button);
                break;
            case EventType.MouseButtonUp:
                onMouseButtonUp(e.button);
                break;
            case EventType.MouseWheel:
                onMouseWheel(e.mouseWheelX, e.mouseWheelY);
                break;
            case EventType.JoystickButtonDown:
                onJoystickButtonDown(e.joystickButton);
                break;
            case EventType.JoystickButtonUp:
                onJoystickButtonUp(e.joystickButton);
                break;
            case EventType.JoystickAxisMotion:
                onJoystickAxisMotion(e.joystickAxis, e.joystickAxisValue);
                break;
            case EventType.Resize:
                onResize(e.width, e.height);
                break;
            case EventType.FocusLoss:
                onFocusLoss();
                break;
            case EventType.FocusGain:
                onFocusGain();
                break;
            case EventType.Quit:
                onQuit();
                break;
            case EventType.UserEvent:
                onUserEvent(e.userCode);
                break;
            default:
                break;
        }
    }

    void onKeyDown(int key) {}
    void onKeyUp(int key) {}
    void onTextInput(dchar code) {}
    void onMouseButtonDown(int button) {}
    void onMouseButtonUp(int button) {}
    void onMouseWheel(int x, int y) {}
    void onJoystickButtonDown(int button) {}
    void onJoystickButtonUp(int button) {}
    void onJoystickAxisMotion(int axis, float value) {}
    void onResize(int width, int height) {}
    void onFocusLoss() {}
    void onFocusGain() {}
    void onQuit() {}
    void onUserEvent(int code) {}
}
