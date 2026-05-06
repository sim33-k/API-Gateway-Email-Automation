#!/usr/bin/env python3
"""Quick test for api_type detection logic"""
from typing import Optional

def detect_api_type_from_paths(endpoints: list) -> str:
    """
    Detect whether the API is public or private by examining endpoint paths.
    Returns 'public' or 'private' based on path prefixes.
    """
    for ep in endpoints:
        path = ep.get('path', '').lower()
        if '/private/' in path:
            return 'private'
        if '/public/' in path:
            return 'public'
    # Default to private if no clear indicator found
    return 'private'


def resolve_template_key(environment: str, api_type: str = 'private') -> Optional[str]:
    """
    Resolve S3 template key from environment and api_type.
    E.g., ('QA', 'private') -> 'templates/private-qa.json'
    """
    if not environment:
        return None
    env = environment.upper().strip()
    api = api_type.lower().strip()
    
    if env not in ['DEV', 'QA', 'UAT', 'PROD']:
        return None
    if api not in ['public', 'private']:
        api = 'private'
    
    return f"templates/{api}-{env.lower()}.json"


# Test cases
print("=" * 60)
print("API Type Detection Tests")
print("=" * 60)

# Test 1: Private API paths in QA
endpoints_private_qa = [
    {"path": "/private/v1/deals/123", "method": "GET"},
    {"path": "/private/v1/admin/panel", "method": "POST"},
]
api_type = detect_api_type_from_paths(endpoints_private_qa)
template = resolve_template_key("QA", api_type)
print(f"\nTest 1 - Private QA paths:")
print(f"  Endpoints: {endpoints_private_qa}")
print(f"  API Type: {api_type}")
print(f"  Template: {template}")
assert api_type == "private", "Should detect private"
assert template == "templates/private-qa.json", "Should resolve private-qa.json"

# Test 2: Public API paths in DEV
endpoints_public_dev = [
    {"path": "/public/v1/health", "method": "GET"},
    {"path": "/public/v1/status", "method": "GET"},
]
api_type = detect_api_type_from_paths(endpoints_public_dev)
template = resolve_template_key("DEV", api_type)
print(f"\nTest 2 - Public DEV paths:")
print(f"  Endpoints: {endpoints_public_dev}")
print(f"  API Type: {api_type}")
print(f"  Template: {template}")
assert api_type == "public", "Should detect public"
assert template == "templates/public-dev.json", "Should resolve public-dev.json"

# Test 3: Mixed but mostly private, default to first found
endpoints_mixed = [
    {"path": "/private/v1/profile", "method": "GET"},
    {"path": "/public/v1/docs", "method": "GET"},
]
api_type = detect_api_type_from_paths(endpoints_mixed)
template = resolve_template_key("UAT", api_type)
print(f"\nTest 3 - Mixed paths (private found first):")
print(f"  Endpoints: {endpoints_mixed}")
print(f"  API Type: {api_type}")
print(f"  Template: {template}")
assert api_type == "private", "Should detect private (first match)"
assert template == "templates/private-uat.json", "Should resolve private-uat.json"

# Test 4: No path prefix, defaults to private
endpoints_no_prefix = [
    {"path": "/v1/customers", "method": "GET"},
    {"path": "/v1/orders", "method": "POST"},
]
api_type = detect_api_type_from_paths(endpoints_no_prefix)
template = resolve_template_key("PROD", api_type)
print(f"\nTest 4 - No prefix paths (defaults to private):")
print(f"  Endpoints: {endpoints_no_prefix}")
print(f"  API Type: {api_type}")
print(f"  Template: {template}")
assert api_type == "private", "Should default to private"
assert template == "templates/private-prod.json", "Should resolve private-prod.json"

# Test 5: Empty endpoints defaults to private
api_type = detect_api_type_from_paths([])
template = resolve_template_key("DEV", api_type)
print(f"\nTest 5 - Empty endpoints (defaults to private):")
print(f"  API Type: {api_type}")
print(f"  Template: {template}")
assert api_type == "private", "Should default to private"
assert template == "templates/private-dev.json", "Should resolve private-dev.json"

print("\n" + "=" * 60)
print("✅ All tests passed!")
print("=" * 60)
