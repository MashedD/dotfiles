"""Owned X11 fixture windows on an explicitly supplied private display."""
import ctypes as c
import time


class FixtureWindow:
    def __init__(self, display_name, kind):
        assert display_name and kind in ('normal', 'dialog')
        self.x = x = c.CDLL('libX11.so.6')
        x.XOpenDisplay.argtypes=[c.c_char_p];x.XOpenDisplay.restype=c.c_void_p
        x.XDefaultRootWindow.argtypes=[c.c_void_p];x.XDefaultRootWindow.restype=c.c_ulong
        x.XCreateSimpleWindow.argtypes=[c.c_void_p,c.c_ulong,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_uint,c.c_ulong,c.c_ulong]
        x.XCreateSimpleWindow.restype=c.c_ulong
        x.XInternAtom.argtypes=[c.c_void_p,c.c_char_p,c.c_int];x.XInternAtom.restype=c.c_ulong
        x.XChangeProperty.argtypes=[c.c_void_p,c.c_ulong,c.c_ulong,c.c_ulong,c.c_int,c.c_int,c.c_void_p,c.c_int]
        x.XSetWMProtocols.argtypes=[c.c_void_p,c.c_ulong,c.POINTER(c.c_ulong),c.c_int]
        x.XStoreName.argtypes=[c.c_void_p,c.c_ulong,c.c_char_p]
        x.XSetClassHint.argtypes=[c.c_void_p,c.c_ulong,c.c_void_p]
        x.XMapWindow.argtypes=[c.c_void_p,c.c_ulong]
        x.XDestroyWindow.argtypes=[c.c_void_p,c.c_ulong]
        x.XPending.argtypes=[c.c_void_p];x.XPending.restype=c.c_int
        x.XNextEvent.argtypes=[c.c_void_p,c.c_void_p]
        x.XFlush.argtypes=[c.c_void_p];x.XCloseDisplay.argtypes=[c.c_void_p]
        self.display=x.XOpenDisplay(display_name.encode())
        assert self.display, 'Cannot open private fixture display'
        self.closed=False
        self.delete_requests=0
        self.window=x.XCreateSimpleWindow(self.display,x.XDefaultRootWindow(self.display),80,180,400,200,0,0,0xeeeeee)
        def atom(name):return x.XInternAtom(self.display,name.encode(),0)
        self.delete=atom('WM_DELETE_WINDOW')
        protocols=(c.c_ulong*1)(self.delete)
        x.XSetWMProtocols(self.display,self.window,protocols,1)
        window_type=(c.c_ulong*1)(atom('_NET_WM_WINDOW_TYPE_'+kind.upper()))
        x.XChangeProperty(self.display,self.window,atom('_NET_WM_WINDOW_TYPE'),atom('ATOM'),32,0,window_type,1)
        class Hint(c.Structure):
            _fields_=[('name',c.c_char_p),('klass',c.c_char_p)]
        hint=Hint(('Narrow'+kind).encode(),b'NarrowFixture')
        x.XSetClassHint(self.display,self.window,c.byref(hint))
        x.XStoreName(self.display,self.window,b'A deliberately long narrow-window title that must truncate cleanly')
        x.XMapWindow(self.display,self.window);x.XFlush(self.display)

    def wait_delete(self, timeout=3):
        class Data(c.Union):
            _fields_=[('l',c.c_long*5),('b',c.c_char*20)]
        class Message(c.Structure):
            _fields_=[('type',c.c_int),('serial',c.c_ulong),('send_event',c.c_int),
                      ('display',c.c_void_p),('window',c.c_ulong),('message_type',c.c_ulong),
                      ('format',c.c_int),('data',Data)]
        class Event(c.Union):
            _fields_=[('message',Message),('pad',c.c_long*24)]
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            while self.x.XPending(self.display):
                event=Event();self.x.XNextEvent(self.display,c.byref(event))
                if event.message.type==33 and event.message.window==self.window and event.message.data.l[0]==self.delete:
                    self.delete_requests+=1
                    self.x.XDestroyWindow(self.display,self.window);self.x.XFlush(self.display)
                    self.closed=True
                    return
            time.sleep(.02)
        raise AssertionError('Close did not send WM_DELETE_WINDOW to the owned fixture')

    def close(self):
        if self.display:
            if not self.closed:self.x.XDestroyWindow(self.display,self.window)
            self.x.XCloseDisplay(self.display)
            self.display=None
