import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')

BUCKET = os.environ['BUCKET']
TEMPLATE_KEY = os.environ['TEMPLATE_KEY']
OVERWRITE_TEMPLATE = os.environ.get('OVERWRITE_TEMPLATE', 'false').lower() == 'true'

SERVICE_NLB_MAP = {
    "admin-portal-service": "none_prod_nlb_port_adminp_service",
    "consumer-service": "none_prod_nlb_port_consumer_service",
    "authentication-service": "none_prod_nlb_port_auth_service"
}

VALID_HTTP_METHODS = {"get", "post", "put", "delete", "patch", "head", "options"}


def _build_output_key(template_key, timestamp):
    template_name = os.path.basename(template_key)
    template_stem, template_ext = os.path.splitext(template_name)

    if not template_stem:
        template_stem = "template"
    if not template_ext:
        template_ext = ".json"

    return f"output/{template_stem}-patched-{timestamp}{template_ext}"


# path_item = {
#     "get": {...},
#     "options": {
#         "x-amazon-apigateway-integration": {
#             "responses": {
#                 "default": {
#                     "responseParameters": {
#                         "method.response.header.Access-Control-Allow-Methods": "'OPTIONS,GET'"
#                     }
#                 }
#             }
#         }
#     }
# }
# method_upper = "POST"  

def _sync_options_allow_methods(path_item, method_upper):
    options = path_item.get("options")
    if not isinstance(options, dict):
        return

    integration = options.get("x-amazon-apigateway-integration")
    if not isinstance(integration, dict):
        return

    responses = integration.get("responses")
    if not isinstance(responses, dict):
        return

    default = responses.get("default")
    if not isinstance(default, dict):
        return

    response_parameters = default.get("responseParameters")
    if not isinstance(response_parameters, dict):
        return

    allow_methods_key = "method.response.header.Access-Control-Allow-Methods"
    allow_methods_value = response_parameters.get(allow_methods_key)
    if not isinstance(allow_methods_value, str):
        return

    methods = [m.strip() for m in allow_methods_value.strip("'").split(",") if m.strip()]
    if "OPTIONS" not in methods:
        methods.insert(0, "OPTIONS")
    if method_upper not in methods:
        methods.append(method_upper)

    response_parameters[allow_methods_key] = f"'{','.join(methods)}'"


def _remove_method_from_options(path_item, method_upper):
    """Remove a method from the OPTIONS Access-Control-Allow-Methods when deleting an endpoint."""
    options = path_item.get("options")
    if not isinstance(options, dict):
        return

    integration = options.get("x-amazon-apigateway-integration")
    if not isinstance(integration, dict):
        return

    responses = integration.get("responses", {})
    default = responses.get("default", {})
    response_parameters = default.get("responseParameters", {})

    allow_methods_key = "method.response.header.Access-Control-Allow-Methods"
    allow_methods_value = response_parameters.get(allow_methods_key)
    if not isinstance(allow_methods_value, str):
        return

    methods = [m.strip() for m in allow_methods_value.strip("'").split(",") if m.strip()]
    methods = [m for m in methods if m != method_upper]

    response_parameters[allow_methods_key] = f"'{','.join(methods)}'"

# ep is one endpoint record (dictionary) in lambda handler
# ep is one JSON object from your parsed input file
# ep example:
# {
# "service_name": "consumer-service",
# "path": "/v1/customers",
# "method": "get",
# "has_auth": true
# }
# ep["method"] (required): HTTP method like get, post, put
# ep["path"] (required): API path like /users/profile


def build_method_block(ep, nlb_var):
    method = ep['method'].upper()
    has_auth = ep.get('has_auth', True)
    request_params_list = ep.get('request_params', [])

    # Build integration request parameters
    # Always include requestId, then add any extra params from the email
    integration_request_params = {
        "integration.request.querystring.requestId": "context.requestId"
    }
    if has_auth:
        integration_request_params["integration.request.header.Authorization"] = \
            "method.request.header.Authorization"

    # Add any extra request params beyond requestId
    for param in request_params_list:
        if param.lower() == "requestid":
            continue  # already hardcoded above
        key = f"integration.request.querystring.{param}"
        value = f"method.request.querystring.{param}"
        integration_request_params[key] = value

    # Build method parameters block
    parameters = []
    if has_auth:
        parameters.append({
            "name": "Authorization",
            "in": "header",
            "required": False,
            "type": "string"
        })

    # Always add requestId
    parameters.append({
        "name": "requestId",
        "in": "query",
        "required": True,
        "type": "string"
    })

    # Add any extra query params
    for param in request_params_list:
        if param.lower() == "requestid":
            continue  # already added above
        parameters.append({
            "name": param,
            "in": "query",
            "required": False,
            "type": "string"
        })

    method_block = {
        "produces": ["application/json"],
        "parameters": parameters,
        "responses": {
            "200": {
                "description": "200 response",
                "schema": {"$ref": "#/definitions/Empty"},
                "headers": {
                    "Access-Control-Allow-Origin": {"type": "string"},
                    "Access-Control-Allow-Methods": {"type": "string"},
                    "Access-Control-Allow-Credentials": {"type": "string"},
                    "Access-Control-Allow-Headers": {"type": "string"}
                }
            }
        },
        "x-amazon-apigateway-integration": {
            "connectionId": "${none_prod_vpc_link_connection_Id}",
            "httpMethod": method,
            "uri": f"${{{nlb_var}}}{ep['path']}",
            "responses": {
                "default": {
                    "statusCode": "200",
                    "responseParameters": {
                        "method.response.header.Access-Control-Allow-Credentials": "'true'",
                        "method.response.header.Access-Control-Allow-Methods": f"'OPTIONS,{method}'",
                        "method.response.header.Access-Control-Allow-Headers": "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
                        "method.response.header.Access-Control-Allow-Origin": "'${front_end_service_url}'"
                    }
                }
            },
            "requestParameters": integration_request_params,
            "connectionType": "VPC_LINK",
            "passthroughBehavior": "when_no_match",
            "type": "http"
        }
    }

    if has_auth:
        method_block["security"] = [{
            "uat-api-authorizer": [
                "aws.cognito.signin.user.admin",
                "email"
            ]
        }]

    options_block = {
        "consumes": ["application/json"],
        "responses": {
            "200": {
                "description": "200 response",
                "headers": {
                    "Access-Control-Allow-Origin": {"type": "string"},
                    "Access-Control-Allow-Methods": {"type": "string"},
                    "Access-Control-Allow-Credentials": {"type": "string"},
                    "Access-Control-Allow-Headers": {"type": "string"}
                }
            }
        },
        "x-amazon-apigateway-integration": {
            "responses": {
                "default": {
                    "statusCode": "200",
                    "responseParameters": {
                        "method.response.header.Access-Control-Allow-Credentials": "'true'",
                        "method.response.header.Access-Control-Allow-Methods": f"'OPTIONS,{method}'",
                        "method.response.header.Access-Control-Allow-Headers": "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent,email,role'",
                        "method.response.header.Access-Control-Allow-Origin": "'${front_end_service_url}'"
                    }
                }
            },
            "requestTemplates": {"application/json": "{ statusCode: 200 }"},
            "passthroughBehavior": "when_no_match",
            "type": "mock"
        }
    }

    return {method.lower(): method_block, "options": options_block}


def lambda_handler(event, context):
    parsed_key = event['parsed_key']
    message_id = event['message_id']

    parsed_obj = s3.get_object(Bucket=BUCKET, Key=parsed_key)
    parsed_data = json.loads(parsed_obj['Body'].read())

    # Support both old format (endpoints) and new format (endpoints_to_add)
    endpoints_to_add = parsed_data.get('endpoints_to_add', parsed_data.get('endpoints', []))
    endpoints_to_delete = parsed_data.get('endpoints_to_delete', [])

    template_obj = s3.get_object(Bucket=BUCKET, Key=TEMPLATE_KEY)
    spec = json.loads(template_obj['Body'].read())
    spec.setdefault('paths', {})

    added = []
    updated = []
    deleted = []
    failed = []

    # ── ADDITIONS / UPDATES ──────────────────────────────────────────────────
    for ep in endpoints_to_add:
        service = ep.get('service_name', '').lower().strip()
        path = ep.get('path', '').strip()
        method = ep.get('method', '').lower().strip()

        if not path:
            failed.append({"path": path, "reason": "Missing path"})
            continue

        if method not in VALID_HTTP_METHODS:
            failed.append({"path": path, "reason": f"Invalid or missing HTTP method: {ep.get('method')}"})
            continue

        if service not in SERVICE_NLB_MAP:
            failed.append({"path": path, "reason": f"Unknown service: {service}"})
            continue

        nlb_var = SERVICE_NLB_MAP[service]
        method_block = build_method_block(ep, nlb_var)

        # Brand new path — add full block including OPTIONS
        if path not in spec['paths']:
            spec['paths'][path] = method_block
            added.append(f"{method.upper()} {path}")
            continue

        path_item = spec['paths'][path]

        # Method already exists — overwrite it
        if method in path_item:
            path_item[method] = method_block[method]
            _sync_options_allow_methods(path_item, method.upper())
            updated.append(f"{method.upper()} {path}")
            continue

        # Path exists, method is new — add method to existing path
        path_item[method] = method_block[method]
        if 'options' not in path_item and 'options' in method_block:
            path_item['options'] = method_block['options']
        _sync_options_allow_methods(path_item, method.upper())
        added.append(f"{method.upper()} {path}")

    # ── DELETIONS ────────────────────────────────────────────────────────────
    for ep in endpoints_to_delete:
        path = ep.get('path', '').strip()
        method = ep.get('method', '')
        method = method.lower().strip() if method else None

        if not path:
            failed.append({"path": path, "reason": "Missing path for deletion"})
            continue

        if path not in spec['paths']:
            failed.append({"path": path, "reason": f"Path not found in template, cannot delete"})
            continue

        path_item = spec['paths'][path]

        # If no method specified, delete the entire path
        if not method:
            del spec['paths'][path]
            deleted.append(f"ALL METHODS {path}")
            continue

        if method not in VALID_HTTP_METHODS:
            failed.append({"path": path, "reason": f"Invalid HTTP method for deletion: {ep.get('method')}"})
            continue

        if method not in path_item:
            failed.append({"path": path, "reason": f"{method.upper()} not found at {path}, cannot delete"})
            continue

        # Remove the method
        del path_item[method]
        _remove_method_from_options(path_item, method.upper())
        deleted.append(f"{method.upper()} {path}")

        # If the path only has OPTIONS left (or is empty), remove the entire path
        remaining = [k for k in path_item.keys() if k != 'options']
        if not remaining:
            del spec['paths'][path]
            deleted.append(f"  → path {path} removed (no methods remaining)")

    # ── OUTPUT ───────────────────────────────────────────────────────────────
    timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
    output_key = _build_output_key(TEMPLATE_KEY, timestamp)

    s3.put_object(
        Bucket=BUCKET,
        Key=output_key,
        Body=json.dumps(spec, indent=2),
        ContentType='application/json'
    )

    if OVERWRITE_TEMPLATE:
        s3.put_object(
            Bucket=BUCKET,
            Key=TEMPLATE_KEY,
            Body=json.dumps(spec, indent=2),
            ContentType='application/json'
        )

    audit = {
        "timestamp": timestamp,
        "message_id": message_id,
        "template_key": TEMPLATE_KEY,
        "output_key": output_key,
        "overwrote_template": OVERWRITE_TEMPLATE,
        "added": added,
        "updated": updated,
        "deleted": deleted,
        "failed": failed
    }

    s3.put_object(
        Bucket=BUCKET,
        Key=f"output/audit-{timestamp}.json",
        Body=json.dumps(audit, indent=2),
        ContentType='application/json'
    )

    if failed:
        print(f"ALERT - endpoints that could not be processed: {json.dumps(failed)}")

    return {
        "statusCode": 200,
        "body": json.dumps(audit)
    }