#include <iostream>
#include <fstream>

#include "parser_top.h"

int process_file (const char * file);
int listen_soc();

int main(int argc, const char * argv[]) {
    if (argc == 2) {
        process_file(argv[1]);
    } else if (argc == 1) {
        listen_soc();
    } else {
        std::cerr << "Usage : " << argv[0] << " stream_file" << std::endl;
        return 1;
    }
    return 0;
}

int process_file (const char * file) {
    using namespace std;

    ifstream f(file);
    if (!f.is_open()) {
        cerr << "Error: Failed to open file " << file << endl;
        return 1;
    }

    char c;
    int error;

    const int batch_size = 8;
    char buff[batch_size+1];
    int sz = batch_size;

    while(sz > 0) {
        sz = 0;
        while(sz < batch_size && f.get(c)) {
            buff[sz++] = c;
        }
        //cout << "x=" << c << endl;
        if ((error = process_data(0, buff, sz)) < 0) {
            std::cout << "Error detected (" << error << ")" << std::endl;
        } else if (error > 0) {
            std::cout << "Info - status (" << error << ")" << std::endl;
        }
    }
    f.close();
    return 0;
}

#include "NKSocket.hpp"
#include <chrono>

int listen_soc() {
    NK::TCPServer s(process_data);

    s.init("127.0.0.1", 8888);
    //s.init("127.0.0.3", 8899);

    auto start_time = std::chrono::steady_clock::now();
    auto end_time   = start_time + static_cast<std::chrono::duration<double>>(60); // secs
    
    while (std::chrono::steady_clock::now() < end_time) {
        s.connect();
        s.process();
    }
    
    return 0;
}
