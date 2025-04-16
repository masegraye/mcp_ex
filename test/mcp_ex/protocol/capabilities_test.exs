defmodule MCPEx.Protocol.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias MCPEx.Protocol.Capabilities

  describe "create_client_capabilities/1" do
    test "creates default capabilities with sampling enabled" do
      capabilities = Capabilities.create_client_capabilities()
      
      assert is_map(capabilities)
      assert Map.has_key?(capabilities, :sampling)
      refute Map.has_key?(capabilities, :roots)
      refute Map.has_key?(capabilities, :experimental)
    end
    
    test "enables the roots capability when specified" do
      capabilities = Capabilities.create_client_capabilities(roots: true)
      
      assert Map.has_key?(capabilities, :roots)
      assert is_map(capabilities.roots)
      refute Map.get(capabilities.roots, :listChanged, false)
    end
    
    test "enables roots with listChanged when specified" do
      capabilities = Capabilities.create_client_capabilities(
        roots: true, 
        roots_list_changed: true
      )
      
      assert Map.has_key?(capabilities, :roots)
      assert Map.get(capabilities.roots, :listChanged, false)
    end
    
    test "disables sampling when specified" do
      capabilities = Capabilities.create_client_capabilities(sampling: false)
      
      refute Map.has_key?(capabilities, :sampling)
    end
    
    test "includes experimental capabilities when provided" do
      experimental = %{custom_feature: %{option: true}}
      capabilities = Capabilities.create_client_capabilities(
        experimental: experimental
      )
      
      assert Map.has_key?(capabilities, :experimental)
      assert capabilities.experimental == experimental
    end
  end
  
  describe "create_server_capabilities/1" do
    test "creates empty server capabilities" do
      capabilities = Capabilities.create_server_capabilities()
      
      assert is_map(capabilities)
      assert Enum.empty?(capabilities)
    end
    
    test "creates server capabilities with resources" do
      capabilities = Capabilities.create_server_capabilities(
        resources: true
      )
      
      assert Map.has_key?(capabilities, :resources)
      assert is_map(capabilities.resources)
      refute Map.get(capabilities.resources, :subscribe, false)
      refute Map.get(capabilities.resources, :listChanged, false)
    end
    
    test "creates server capabilities with full resources options" do
      capabilities = Capabilities.create_server_capabilities(
        resources: true,
        resources_subscribe: true,
        resources_list_changed: true
      )
      
      assert Map.has_key?(capabilities, :resources)
      assert Map.get(capabilities.resources, :subscribe, false)
      assert Map.get(capabilities.resources, :listChanged, false)
    end
    
    test "creates server capabilities with tools" do
      capabilities = Capabilities.create_server_capabilities(
        tools: true
      )
      
      assert Map.has_key?(capabilities, :tools)
      assert is_map(capabilities.tools)
      refute Map.get(capabilities.tools, :listChanged, false)
    end
    
    test "creates server capabilities with tools and listChanged" do
      capabilities = Capabilities.create_server_capabilities(
        tools: true,
        tools_list_changed: true
      )
      
      assert Map.has_key?(capabilities, :tools)
      assert Map.get(capabilities.tools, :listChanged, false)
    end
    
    test "creates server capabilities with prompts" do
      capabilities = Capabilities.create_server_capabilities(
        prompts: true,
        prompts_list_changed: true
      )
      
      assert Map.has_key?(capabilities, :prompts)
      assert Map.get(capabilities.prompts, :listChanged, false)
    end
    
    test "creates server capabilities with logging" do
      capabilities = Capabilities.create_server_capabilities(
        logging: true
      )
      
      assert Map.has_key?(capabilities, :logging)
      assert is_map(capabilities.logging)
    end
    
    test "includes experimental capabilities when provided" do
      experimental = %{custom_feature: %{option: true}}
      capabilities = Capabilities.create_server_capabilities(
        experimental: experimental
      )
      
      assert Map.has_key?(capabilities, :experimental)
      assert capabilities.experimental == experimental
    end
  end
  
  describe "has_capability?/3" do
    test "checks top-level capability existence" do
      capabilities = %{
        resources: %{subscribe: true},
        tools: %{}
      }
      
      assert Capabilities.has_capability?(capabilities, :resources)
      assert Capabilities.has_capability?(capabilities, :tools)
      refute Capabilities.has_capability?(capabilities, :prompts)
    end
    
    test "checks sub-capability existence" do
      capabilities = %{
        resources: %{
          subscribe: true,
          listChanged: false
        }
      }
      
      assert Capabilities.has_capability?(capabilities, :resources, :subscribe)
      refute Capabilities.has_capability?(capabilities, :resources, :listChanged)
      refute Capabilities.has_capability?(capabilities, :resources, :unknown)
      refute Capabilities.has_capability?(capabilities, :prompts, :listChanged)
    end
  end
  
  describe "negotiate_version/2" do
    test "returns common version when both support the same version" do
      client_version = "2025-03-26"
      server_versions = ["2025-03-26", "2024-11-05"]
      
      assert {:ok, "2025-03-26"} = Capabilities.negotiate_version(client_version, server_versions)
    end
    
    test "returns latest common version when multiple matches" do
      client_versions = ["2025-03-26", "2024-11-05"]
      server_versions = ["2025-03-26", "2024-11-05", "2024-05-23"]
      
      assert {:ok, "2025-03-26"} = Capabilities.negotiate_version(client_versions, server_versions)
    end
    
    test "returns error when no common version" do
      client_version = "2025-03-26"
      server_versions = ["2024-11-05", "2024-05-23"]
      
      assert {:error, _} = Capabilities.negotiate_version(client_version, server_versions)
    end
  end
  
  describe "validate_capability_support/2" do
    test "validates required client capabilities with supported server capabilities" do
      client_required_capabilities = [:sampling]
      server_capabilities = %{
        resources: %{subscribe: true},
        tools: %{},
        sampling: %{}
      }
      
      assert :ok = Capabilities.validate_capability_support(client_required_capabilities, server_capabilities)
    end
    
    test "returns error when required capability is not supported" do
      client_required_capabilities = [:sampling, :roots]
      server_capabilities = %{
        resources: %{subscribe: true},
        tools: %{},
        sampling: %{}
      }
      
      assert {:error, _} = Capabilities.validate_capability_support(client_required_capabilities, server_capabilities)
    end
  end
end