#ifndef __NK_SOCKET__
#define __NK_SOCKET__

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <errno.h>
#include <cstring>
#include <unistd.h>

#include <iostream>
#include <map>
#include <stdio.h>

#define NOISE     0
#define DEBUG1    1
#define DEBUG2    2
#define INFO      10
#define CRITICAL  100

#define LOG_LVL DEBUG1

#if LOG_LVL == 0
#   define LOG_0(_FMT_, ARGS...)   log_(NOIS, _FMT_, ARGS)
#   define LOG_1(_FMT_, ARGS...)   log_(DBG1, _FMT_, ARGS)
#   define LOG_2(_FMT_, ARGS...)   log_(DBG2, _FMT_, ARGS)
#   define LOG_10(_FMT_, ARGS...)  log_(INFO, _FMT_, ARGS)
#   define LOG_100(_FMT_, ARGS...) log_(CRIT, _FMT_, ARGS)
#elif LOG_LVL == 1
#   define LOG_0(_FMT_, ARGS...)
#   define LOG_1(_FMT_, ARGS...)   log_(DBG1, _FMT_, ARGS)
#   define LOG_2(_FMT_, ARGS...)   log_(DBG2, _FMT_, ARGS)
#   define LOG_10(_FMT_, ARGS...)  log_(INFO, _FMT_, ARGS)
#   define LOG_100(_FMT_, ARGS...) log_(CRIT, _FMT_, ARGS)
#elif LOG_LVL == 2
#   define LOG_0(_FMT_, ARGS...)
#   define LOG_1(_FMT_, ARGS...)
#   define LOG_2(_FMT_, ARGS...)   log_(DBG2, _FMT_, ARGS)
#   define LOG_10(_FMT_, ARGS...)  log_(INFO, _FMT_, ARGS)
#   define LOG_100(_FMT_, ARGS...) log_(CRIT, _FMT_, ARGS)
#elif LOG_LVL == 10
#   define LOG_0(_FMT_, ARGS...)
#   define LOG_1(_FMT_, ARGS...)
#   define LOG_2(_FMT_, ARGS...)
#   define LOG_10(_FMT_, ARGS...)  log_(INFO, _FMT_, ARGS)
#   define LOG_100(_FMT_, ARGS...) log_(CRIT, _FMT_, ARGS)
#elif LOG_LVL == 100
#   define LOG_0(_FMT_, ARGS...)
#   define LOG_1(_FMT_, ARGS...)
#   define LOG_2(_FMT_, ARGS...)
#   define LOG_10(_FMT_, ARGS...)
#   define LOG_100(_FMT_, ARGS...) log_(CRIT, _FMT_, ARGS)
#endif

#define log_(LVL, fmt, args...) printf("[" # LVL "] %04d - " fmt "\n", __LINE__, args)

#define log_fun(LVL, fmt, args...) LOG_ ## LVL(fmt, args)
#define log(LVL, fmt, args...) log_fun(LVL, fmt, args)

namespace NK {
    class TCPServer {
    public:
        typedef int (* stream_cb_t) (int id, char * data, size_t size);
        enum class State
        {       FAILED = -1,
                UNINITILIZED,
                LISTENING
                }   _st  = State::UNINITILIZED;

        static constexpr int stream_size = 8;

    private:
        std::map<long, sockaddr_in> _srv_soc;
        std::map<long, sockaddr_in> _clt_soc;

        stream_cb_t                 _clt_stream_cb;
        
        fd_set                      _clt_fds;
        int                         _clt_num = 0;
    public:
        
        TCPServer(stream_cb_t cb) : _clt_stream_cb(cb) {
            FD_ZERO(&_clt_fds);
        }
        
        int init(const char * ip, int port) {
            sockaddr_in _ssc = {AF_INET, ntohs(port), { INADDR_ANY }, "" };
            int _sfd = 0;

            // 1. socket
            if ((_sfd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0)) < 0)
                return static_cast<int>(_st = State::FAILED);

            // 2. prepare sockaddr / port
            if (inet_aton(ip, &_ssc.sin_addr) < 0)
                return static_cast<int>(_st = State::FAILED);
            
            // 3. bind
            if (bind(_sfd, (sockaddr *) &_ssc, sizeof(sockaddr_in)) < 0)
                return static_cast<int>(_st = State::FAILED);
            
            // 4. listen
            if (listen(_sfd, 10) < 0)
                return static_cast<int>(_st = State::FAILED);

            log(INFO, "[%03d] %s", _sfd, "server started");
            _srv_soc.insert(std::make_pair(_sfd, _ssc));
            
            _st = State::LISTENING;
            return 0;
        }

        int connect () {
            // 5. accept
            int sin_size = sizeof(sockaddr_in);
            int flags = 1;
            for(auto & srv : _srv_soc) {
                int _sfd = srv.first;
                log(NOISE, "[%03d] %s", _sfd, "checking server");
                sockaddr_in _csc = {};
                errno = 0; // reset error
                int _cfd = accept
                    (    _sfd,
                         (struct sockaddr *) & _csc,
                         (socklen_t *)       & sin_size );

                switch (errno) {
                case 0:
                    _clt_soc.insert(std::make_pair(_cfd, _csc));
                    if (setsockopt(_cfd, IPPROTO_TCP,
                                   TCP_NODELAY, (char *)&flags,  sizeof(int))) {
                        // warn socopt error
                    }
                    FD_SET(_cfd, &_clt_fds);
                    if (_cfd >= _clt_num)
                        _clt_num = _cfd + 1;
                    log(NOISE, "<%03d> %s", _cfd, "client received");
                    break;
                default:
                    // Some error on socket
                    // mark it stale
                case EAGAIN:
                    /* no client present */
                    errno = 0;
                    continue;
                }
            }
            return 0;
        }

        int process() {
            struct timeval tv = { 5, 0 };

            fd_set  __clt_fds = _clt_fds;
            //std::memcpy(&__clt_fds, &_clt_fds, sizeof(_clt_fds));

            switch(select(_clt_num, &__clt_fds, NULL, NULL, &tv)) {
            case -1:
                perror("ERROR in client select()");
                errno = 0;
            case 0:
                log(NOISE, "<%03d> %s", _clt_num, "time out in select");
                return 0;
            default:
                log(NOISE, "%s", "action on some client");
                break;
            }

            constexpr int size_buff = 10000;
            char _buf[size_buff + 1];
            int  _got = 0;
            for(auto & clt : _clt_soc) {
                int _cfd = clt.first;
                log(NOISE, "<%03d> %s", _cfd, "checking client");
                if (! FD_ISSET(_cfd, &__clt_fds)) continue;
                bool _read = true;
                do {
                    int got = recv(_cfd, _buf + _got,
                                   (size_buff - _got > stream_size
                                    ? stream_size : size_buff - _got),
                                   MSG_DONTWAIT);
                    switch (got) {
                    default:
                        log(NOISE, "<%03d> recv size = %d/%d",
                            _cfd, got, got + _got);
                        // stream here
                        _clt_stream_cb(_cfd, _buf + _got, got);
                        _got += got;
                        continue;
                    case 0:
                        // client has clean disconnected...
                        // do cleanup
                        log(INFO, "<%03d> %s", _cfd, "client disconnected");
                        FD_CLR(_cfd, &_clt_fds);
                        if (_clt_num == _cfd + 1)
                            _clt_num--;
                        close(_cfd);
                        _read = false;
                        break;
                    case -1:
                        switch(errno) {
                        case EAGAIN: // no more data present.
                            errno = 0;
                            _read = false;
                            break;
                        default:
                            // may be release client
                            // do cleanup
                            errno = 0;
                        }
                    }
                } while(_read);

                if (_got > 0) {
                    _buf[_got] = '\0';

                    //std::cout << "GOT FROM CLT (" << _cfd
                    //          << ") [" << _buf << "]" << std::endl;
                }
            }
            return 0;
        }
    };
}
    
#endif //__NK_SOCKET__
