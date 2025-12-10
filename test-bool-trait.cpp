#include <iostream>
#include <nlohmann/json.hpp>
#include <type_traits>

int main() {
    // Test if bool satisfies the requirements
    std::cout << "is_constructible<json, bool>: "
              << std::is_constructible<nlohmann::json, bool>::value << std::endl;

    std::cout << "is_constructible<json, const bool&>: "
              << std::is_constructible<nlohmann::json, const bool&>::value << std::endl;

    std::cout << "is_constructible<json, bool&>: "
              << std::is_constructible<nlohmann::json, bool&>::value << std::endl;

    // Try different ways to construct
    bool b = true;
    const bool cb = true;

    try {
        nlohmann::json j1 = b;  // Assignment
        std::cout << "Assignment from bool works: " << j1 << std::endl;
    } catch (...) {
        std::cout << "Assignment from bool failed" << std::endl;
    }

    try {
        nlohmann::json j2(b);  // Direct construction
        std::cout << "Direct construction from bool& works: " << j2 << std::endl;
    } catch (...) {
        std::cout << "Direct construction from bool& failed" << std::endl;
    }

    try {
        nlohmann::json j3(cb);  // Const ref construction
        std::cout << "Construction from const bool& works: " << j3 << std::endl;
    } catch (...) {
        std::cout << "Construction from const bool& failed" << std::endl;
    }

    try {
        nlohmann::json j4(true);  // Literal construction
        std::cout << "Construction from bool literal works: " << j4 << std::endl;
    } catch (...) {
        std::cout << "Construction from bool literal failed" << std::endl;
    }

    return 0;
}