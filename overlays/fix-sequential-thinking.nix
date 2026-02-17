{ lib, nixmcp, pkgs, ... }:

{
  # Override the sequential-thinking-mcp package to fix the tuple issue
  nixpkgs.overlays = [
    (_final: _prev: {
      # Create a fixed version of sequential-thinking-mcp
      sequential-thinking-mcp-fixed =
        let
          originalPkg = nixmcp.packages.${pkgs.stdenv.hostPlatform.system}.sequential-thinking-mcp;
        in
        originalPkg.overrideAttrs (oldAttrs: {
          postPatch = (oldAttrs.postPatch or "") + ''
                        # Fix the MCP types issue
                        echo "Patching sequential-thinking server.py..."
            
                        # Create a wrapper that fixes the return types
                        cat > sequential_thinking_mcp/server_wrapper.py << 'EOF'
            from .server import *
            from .server import SequentialThinkingServer as _OriginalServer

            # Monkey patch to fix the handlers
            original_setup = _OriginalServer._setup_handlers

            def patched_setup_handlers(self):
                original_setup(self)
    
                # Get the original handlers
                list_tools_handler = self.server._tool_handlers.get('list_tools')
                list_resources_handler = self.server._resource_handlers.get('list_resources')
    
                # Wrap them to fix return types
                if list_tools_handler:
                    async def fixed_list_tools():
                        result = await list_tools_handler()
                        # If it's already a tuple, return it; otherwise wrap it
                        if isinstance(result, tuple):
                            return result
                        return (result.tools,) if hasattr(result, 'tools') else result
                    self.server._tool_handlers['list_tools'] = fixed_list_tools
    
                if list_resources_handler:
                    async def fixed_list_resources():
                        result = await list_resources_handler()
                        # If it's already a tuple, return it; otherwise wrap it
                        if isinstance(result, tuple):
                            return result
                        return (result.resources,) if hasattr(result, 'resources') else result
                    self.server._resource_handlers['list_resources'] = fixed_list_resources

            _OriginalServer._setup_handlers = patched_setup_handlers
            EOF

                        # Update __init__.py to use the wrapper
                        echo "from .server_wrapper import *" >> sequential_thinking_mcp/__init__.py
          '';
        });
    })
  ];
}
