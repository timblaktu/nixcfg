#include <iostream>
#include <nlohmann/json.hpp>

int main() {
    // Test 1: The exact pattern from docling-parse to_json.h:165
    {
        nlohmann::json result;
        bool val = true;
        try {
            result = val; // This is what fails according to the error
            std::cout << "Test 1 (assignment): SUCCESS - " << result << std::endl;
        } catch (...) {
            std::cout << "Test 1 (assignment): FAILED" << std::endl;
        }
    }

    // Test 2: The pattern from page_cell.h - push_back with bool&
    {
        nlohmann::json cell = nlohmann::json::array();
        bool widget = true;
        bool left_to_right = false;
        try {
            cell.push_back(widget);        // Line 19 in error
            cell.push_back(left_to_right); // Line 20 in error
            std::cout << "Test 2 (push_back): SUCCESS - " << cell << std::endl;
        } catch (...) {
            std::cout << "Test 2 (push_back): FAILED" << std::endl;
        }
    }

    // Test 3: Constructor with bool reference (the third error)
    {
        bool val = true;
        try {
            nlohmann::json j(val); // Constructor with bool&
            std::cout << "Test 3 (constructor): SUCCESS - " << j << std::endl;
        } catch (...) {
            std::cout << "Test 3 (constructor): FAILED" << std::endl;
        }
    }

    // Test 4: Suggested fix - using explicit constructor
    {
        nlohmann::json result;
        bool val = true;
        try {
            result = nlohmann::json(val);
            std::cout << "Test 4 (explicit constructor): SUCCESS - " << result << std::endl;
        } catch (...) {
            std::cout << "Test 4 (explicit constructor): FAILED" << std::endl;
        }
    }

    // Test 5: Using boolean_t type
    {
        nlohmann::json result;
        bool val = true;
        try {
            result = nlohmann::json::boolean_t(val);
            std::cout << "Test 5 (boolean_t): SUCCESS - " << result << std::endl;
        } catch (...) {
            std::cout << "Test 5 (boolean_t): FAILED" << std::endl;
        }
    }

    return 0;
}