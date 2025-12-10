#include <iostream>
#include <nlohmann/json.hpp>

int main() {
    nlohmann::json cell = nlohmann::json::array();

    // Test 1: push_back with bool lvalue (what docling-parse is doing)
    {
        bool widget = true;
        try {
            // This is exactly what fails in docling-parse
            cell.push_back(widget);
            std::cout << "push_back(bool&) works" << std::endl;
        } catch (...) {
            std::cout << "push_back(bool&) FAILED - no implicit conversion" << std::endl;
        }
    }

    // Test 2: push_back with bool rvalue
    {
        try {
            cell.push_back(true);  // rvalue
            std::cout << "push_back(true) works" << std::endl;
        } catch (...) {
            std::cout << "push_back(true) FAILED" << std::endl;
        }
    }

    // Test 3: push_back with explicit json construction
    {
        bool widget = true;
        try {
            cell.push_back(nlohmann::json(widget));
            std::cout << "push_back(json(bool&)) works" << std::endl;
        } catch (...) {
            std::cout << "push_back(json(bool&)) FAILED" << std::endl;
        }
    }

    // Test 4: push_back with move
    {
        bool widget = true;
        try {
            cell.push_back(std::move(widget));
            std::cout << "push_back(std::move(bool&)) works" << std::endl;
        } catch (...) {
            std::cout << "push_back(std::move(bool&)) FAILED" << std::endl;
        }
    }

    std::cout << "Final array: " << cell << std::endl;
    return 0;
}