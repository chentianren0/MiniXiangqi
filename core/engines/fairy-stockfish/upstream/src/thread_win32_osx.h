/*
  Stockfish, a UCI chess playing engine derived from Glaurung 2.1
  Copyright (C) 2004-2022 The Stockfish developers (see AUTHORS file)

  Stockfish is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Stockfish is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef THREAD_WIN32_OSX_H_INCLUDED
#define THREAD_WIN32_OSX_H_INCLUDED

#include <thread>

/// Search recursively keeps large move-picker storage at every active ply.
/// Reserve enough stack for MAX_PLY searches built with the largest move list;
/// supported operating systems back the reservation with pages as it is used.

#if defined(__APPLE__) || defined(__MINGW32__) || defined(__MINGW64__) || defined(USE_PTHREADS)

#include <pthread.h>

namespace Stockfish {

static const size_t TH_STACK_SIZE = 64 * 1024 * 1024;

template <class T, class P = std::pair<T*, void(T::*)()>>
void* start_routine(void* ptr)
{
   P* p = reinterpret_cast<P*>(ptr);
   (p->first->*(p->second))(); // Call member function pointer
   delete p;
   return NULL;
}

class NativeThread {

   pthread_t thread;

public:
  template<class T, class P = std::pair<T*, void(T::*)()>>
  explicit NativeThread(void(T::*fun)(), T* obj) {
    pthread_attr_t attr_storage, *attr = &attr_storage;
    pthread_attr_init(attr);
    pthread_attr_setstacksize(attr, TH_STACK_SIZE);
    pthread_create(&thread, attr, start_routine<T>, new P(obj, fun));
  }
  void join() { pthread_join(thread, NULL); }
  void detach() { pthread_detach(thread); }
};

} // namespace Stockfish

#elif defined(_WIN32) && defined(_MSC_VER)

/// Under MSVC neither mechanism above is available: there is no
/// pthread_attr_setstacksize(), and std::thread cannot be asked for a stack
/// size, so a search thread would run on the 1 MiB the linker reserves by
/// default. Built with ALLVARS, MAX_MOVES is 8192, so the ExtMove array every
/// MovePicker holds is 64 KiB, and search() and qsearch() nest one MovePicker per
/// ply on top of a StateInfo that is itself larger on a large board. At the
/// engine's MAX_PLY, an 8 MiB stack is not enough; on Windows a stack overflow
/// terminates the process rather than raising something a caller could report.
/// _beginthreadex() is the one creation path that takes a stack size, so ask it
/// for the same 64 MiB the pthread branch asks for. STACK_SIZE_PARAM_IS_A_RESERVATION
/// makes that a reservation of address space; without it the size would be an
/// initial commit, charging 64 MiB of committed memory per thread before it is
/// needed. Pages are committed as the stack grows into them either way.
/// MinGW does not reach here: it is matched above and keeps pthreads.

#include <process.h>

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#  define NOMINMAX // Disable macros min() and max()
#endif
#include <windows.h>
#undef WIN32_LEAN_AND_MEAN

namespace Stockfish {

static const size_t TH_STACK_SIZE = 64 * 1024 * 1024;

template <class T, class P = std::pair<T*, void(T::*)()>>
unsigned __stdcall start_routine(void* ptr)
{
   P* p = reinterpret_cast<P*>(ptr);
   (p->first->*(p->second))(); // Call member function pointer
   delete p;
   return 0;
}

class NativeThread {

   HANDLE thread;

public:
  template<class T, class P = std::pair<T*, void(T::*)()>>
  explicit NativeThread(void(T::*fun)(), T* obj) {
    thread = reinterpret_cast<HANDLE>(_beginthreadex(
               NULL, unsigned(TH_STACK_SIZE), start_routine<T>, new P(obj, fun),
               STACK_SIZE_PARAM_IS_A_RESERVATION, NULL));
  }
  void join() { WaitForSingleObject(thread, INFINITE); CloseHandle(thread); }
  void detach() { CloseHandle(thread); }
};

} // namespace Stockfish

#else // Default case: use STL classes

namespace Stockfish {

typedef std::thread NativeThread;

} // namespace Stockfish

#endif

#endif // #ifndef THREAD_WIN32_OSX_H_INCLUDED
