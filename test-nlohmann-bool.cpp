#include <iostream>
#include <nlohmann/json.hpp>

int main() {
    bool val = true;

    // Test 1: Direct constructor
    try {
        nlohmann::json j1(val);
        std::cout << "Direct constructor works: " << j1 << std::endl;
    } catch (const std::exception& e) {
        std::cout << "Direct constructor failed: " << e.what() << std::endl;
    }

    // Test 2: Assignment
    try {
        nlohmann::json j2;
        j2 = val;
        std::cout << "Assignment works: " << j2 << std::endl;
    } catch (const std::exception& e) {
        std::cout << "Assignment failed: " << e.what() << std::endl;
    }

    // Test 3: Parse
    try {
        nlohmann::json j3 = nlohmann::json::parse("true");
        std::cout << "Parse works: " << j3 << std::endl;
    } catch (const std::exception& e) {
        std::cout << "Parse failed: " << e.what() << std::endl;
    }

    return 0;
}