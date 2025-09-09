# Tests Module - Enhanced testing framework for validated scripts
{ config, lib, pkgs, collectScriptTests, writers, ... }:

with lib;

let
  cfg = config.validatedScripts;
  
  # Enhanced test utilities for script validation
  testUtils = {
    
    # Test that a script exists and is executable
    testScriptExists = scriptPackage: scriptName: writers.testBash "test-${scriptName}-exists" ''
      script_path="${scriptPackage}/bin/${scriptName}"
      
      # Check if script file exists
      if [[ ! -f "$script_path" ]]; then
        echo "❌ Script file does not exist: $script_path"
        exit 1
      fi
      
      # Check if script is executable
      if [[ ! -x "$script_path" ]]; then
        echo "❌ Script is not executable: $script_path"
        exit 1
      fi
      
      echo "✅ Script exists and is executable: $script_path"
    '';
    
    # Test that a script responds to --help or -h
    testScriptHelp = scriptPackage: scriptName: writers.testBash "test-${scriptName}-help" ''
      script_path="${scriptPackage}/bin/${scriptName}"
      
      # Try various help patterns
      help_found=false
      
      for help_arg in "--help" "-h" "help"; do
        if "$script_path" "$help_arg" >/dev/null 2>&1; then
          help_found=true
          break
        fi
      done
      
      if $help_found; then
        echo "✅ Script responds to help: $script_path"
      else
        echo "⚠️  Script does not respond to common help arguments: $script_path"
        # Don't fail - this is just a warning
      fi
    '';
    
    # Test script for common issues (shellcheck-like basic checks)
    testScriptQuality = scriptPackage: scriptName: language: writers.testBash "test-${scriptName}-quality" ''
      script_path="${scriptPackage}/bin/${scriptName}"
      
      case "${language}" in
        "bash")
          # Check for bash best practices
          if command -v shellcheck >/dev/null 2>&1; then
            if shellcheck "$script_path" 2>/dev/null; then
              echo "✅ Shellcheck passed for: $script_path"
            else
              echo "⚠️  Shellcheck warnings for: $script_path"
              # Don't fail on warnings, just notify
            fi
          else
            echo "ℹ️  Shellcheck not available, skipping quality check for: $script_path"
          fi
          ;;
        "python3")
          # Basic Python syntax check
          if python3 -m py_compile "$script_path" 2>/dev/null; then
            echo "✅ Python syntax check passed for: $script_path"
          else
            echo "❌ Python syntax errors in: $script_path"
            exit 1
          fi
          ;;
        "powershell")
          # PowerShell is harder to validate without pwsh, just check file structure
          if grep -q "param\|Write-Host\|function" "$script_path" 2>/dev/null; then
            echo "✅ PowerShell structure looks reasonable for: $script_path"
          else
            echo "⚠️  PowerShell script structure unclear for: $script_path"
          fi
          ;;
        *)
          echo "ℹ️  No quality checks available for language '${language}' in: $script_path"
          ;;
      esac
    '';
    
    # Integration test - test script in a clean environment
    testScriptInCleanEnv = scriptPackage: scriptName: testCommand: writers.testBash "test-${scriptName}-clean-env" ''
      # Run script in a minimal environment
      env -i PATH="${pkgs.coreutils}/bin:${pkgs.bash}/bin" \
          HOME="/tmp" \
          ${testCommand}
      
      echo "✅ Clean environment test passed for: ${scriptName}"
    '';
    
  };
  
  # Generate comprehensive test suites for all scripts
  generateComprehensiveTests = scripts:
    lib.mapAttrs (scriptName: scriptDrv:
      let
        language = scriptDrv.passthru.language or "bash";
        customTests = scriptDrv.passthru.tests or {};
      in
      customTests // {
        # Add standard tests for all scripts
        exists = testUtils.testScriptExists scriptDrv scriptName;
        help = testUtils.testScriptHelp scriptDrv scriptName;
        quality = testUtils.testScriptQuality scriptDrv scriptName language;
      }
    ) scripts;
  
  # Enhanced integration test helpers
  enhancedTestUtils = {
    
    testScriptIntegration = { script, command, expectedOutput ? null, shouldSucceed ? true }:
      writers.testBash "integration-${script.pname or script.name}" ''
        echo "🧪 Running integration test for ${script.pname or script.name}"
        
        # Test script execution
        if ${if shouldSucceed then "!" else ""} ${script}/bin/${script.pname or script.name} ${command} > test_output.txt 2>&1; then
          ${if shouldSucceed then ''
            echo "❌ Script execution failed unexpectedly"
            cat test_output.txt
            exit 1
          '' else ''
            echo "✅ Script correctly failed as expected"
          ''}
        else
          ${if shouldSucceed then ''
            echo "✅ Script executed successfully"
          '' else ''
            echo "❌ Script was expected to fail but succeeded"
            exit 1
          ''}
        fi
        
        ${lib.optionalString (expectedOutput != null) ''
          if grep -q "${expectedOutput}" test_output.txt; then
            echo "✅ Expected output found: ${expectedOutput}"
          else
            echo "❌ Expected output not found: ${expectedOutput}"
            echo "Actual output:"
            cat test_output.txt
            exit 1
          fi
        ''}
        
        echo "✅ Integration test passed for ${script.pname or script.name}"
      '';
    
    # Cross-platform compatibility test framework
    testCrossPlatform = { script, platforms ? [ "linux" ], skipOn ? [] }:
      let
        currentPlatform = pkgs.stdenv.hostPlatform.system;
        platformName = if pkgs.stdenv.isLinux then "linux"
                      else if pkgs.stdenv.isDarwin then "darwin"
                      else "unknown";
        shouldSkip = builtins.elem platformName skipOn;
        shouldTest = builtins.elem platformName platforms && !shouldSkip;
      in
      if shouldTest then
        writers.testBash "cross-platform-${script.pname or script.name}" ''
          echo "🌍 Running cross-platform test for ${script.pname or script.name} on ${platformName}"
          
          # Test basic script availability and execution
          if [ -x "${script}/bin/${script.pname or script.name}" ]; then
            echo "✅ Script executable found"
          else
            echo "❌ Script executable not found"
            exit 1
          fi
          
          # Test help/version output (most scripts should support this)
          if ${script}/bin/${script.pname or script.name} --help >/dev/null 2>&1 || 
             ${script}/bin/${script.pname or script.name} -h >/dev/null 2>&1 ||
             ${script}/bin/${script.pname or script.name} help >/dev/null 2>&1; then
            echo "✅ Script provides help information"
          else
            echo "⚠️  Script does not provide standard help (this may be OK)"
          fi
          
          echo "✅ Cross-platform test passed on ${platformName}"
        ''
      else
        writers.testBash "cross-platform-skip-${script.pname or script.name}" ''
          echo "⏭️  Skipping cross-platform test for ${script.pname or script.name}"
          echo "   Platform: ${platformName} (not in ${toString platforms} or in skip list)"
        '';
    
    # Performance benchmark helper
    testPerformance = { script, command, maxDurationSeconds ? 30 }:
      writers.testBash "performance-${script.pname or script.name}" ''
        echo "⏱️  Running performance test for ${script.pname or script.name}"
        
        start_time=$(date +%s)
        if timeout ${toString maxDurationSeconds}s ${script}/bin/${script.pname or script.name} ${command} >/dev/null 2>&1; then
          end_time=$(date +%s)
          duration=$((end_time - start_time))
          
          echo "✅ Script completed in ''${duration}s (limit: ${toString maxDurationSeconds}s)"
          
          if [ $duration -gt ${toString maxDurationSeconds} ]; then
            echo "⚠️  Script took longer than expected but within timeout"
          fi
        else
          echo "❌ Script timed out or failed within ${toString maxDurationSeconds}s"
          exit 1
        fi
        
        echo "✅ Performance test passed"
      '';
    
    # Dependency verification test
    testDependencies = { script, requiredCommands ? [], requiredPythonModules ? [] }:
      writers.testBash "dependencies-${script.pname or script.name}" ''
        echo "🔗 Testing dependencies for ${script.pname or script.name}"
        
        # Test required commands
        ${lib.concatMapStringsSep "\n" (cmd: ''
          if command -v ${cmd} >/dev/null 2>&1; then
            echo "✅ Required command available: ${cmd}"
          else
            echo "❌ Required command missing: ${cmd}"
            exit 1
          fi
        '') requiredCommands}
        
        # Test required Python modules (if any)
        ${lib.concatMapStringsSep "\n" (module: ''
          if python3 -c "import ${module}" 2>/dev/null; then
            echo "✅ Required Python module available: ${module}"
          else
            echo "❌ Required Python module missing: ${module}"
            exit 1
          fi
        '') requiredPythonModules}
        
        echo "✅ All dependencies verified"
      '';
    
  };
  
  # Cross-language integration tests
  integrationTests = {
    
    # Test that all validated scripts can be found in PATH
    all-scripts-in-path = writers.testBash "test-all-validated-scripts-in-path" ''
      echo "Testing that all validated scripts are available in PATH..."
      
      scripts_found=0
      scripts_missing=0
      
      # Test example scripts that should be available
      for script in hello-validated system-info-py; do
        if command -v "$script" >/dev/null 2>&1; then
          echo "✅ Found script in PATH: $script"
          ((scripts_found++))
        else
          echo "❌ Missing script from PATH: $script"
          ((scripts_missing++))
        fi
      done
      
      echo "Scripts found: $scripts_found"
      echo "Scripts missing: $scripts_missing"
      
      if (( scripts_missing > 0 )); then
        echo "❌ Some validated scripts are missing from PATH"
        exit 1
      fi
      
      echo "✅ All expected validated scripts found in PATH"
    '';
    
    # Test that environment variable is set correctly
    environment-setup = writers.testBash "test-validated-scripts-environment" ''
      if [[ "$NIXCFG_VALIDATED_SCRIPTS_ENABLED" == "1" ]]; then
        echo "✅ Validated scripts environment variable is set"
      else
        echo "⚠️  Validated scripts environment variable not set (may be expected in some environments)"
      fi
    '';
    
    # Multi-language ecosystem test
    ecosystem-validation = writers.testBash "test-validated-scripts-ecosystem" ''
      echo "🌐 Testing validated scripts ecosystem integration"
      
      # Test bash scripts
      if command -v hello-validated >/dev/null 2>&1; then
        echo "✅ Bash script ecosystem active"
      else
        echo "⚠️  Bash script ecosystem not fully active"
      fi
      
      # Test Python scripts
      if command -v system-info-py >/dev/null 2>&1; then
        echo "✅ Python script ecosystem active"
      else
        echo "⚠️  Python script ecosystem not fully active"
      fi
      
      # Test PowerShell scripts (on WSL systems)
      if [[ -n "$WSL_DISTRO_NAME" ]] && command -v powershell.exe >/dev/null 2>&1; then
        echo "✅ PowerShell ecosystem potentially active"
      else
        echo "ℹ️  PowerShell ecosystem not applicable or not active"
      fi
      
      echo "✅ Ecosystem validation complete"
    '';
    
  };
  
in {
  # Test utilities are provided via _module.args, no options needed
  
  config = mkIf (cfg.enable && cfg.enableTests) {
    
    # Make test utilities available to other modules
    _module.args.scriptTestUtils = testUtils;
    
    # Test generation is handled by the main module
    
    # Tests are handled by the main validated-scripts module
    # This module just provides test utilities and framework
    
  };
}