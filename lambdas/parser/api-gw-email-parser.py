import json
import boto3
import email
import os
import requests
from typing import Optional
from groq import Groq

client = Groq(api_key=os.environ["API_KEY"])
s3 = boto3.client('s3')

BUCKET = os.environ['BUCKET']


def parse_email_with_ai(body: str, sender: str, subject: str) -> dict:
    prompt = f"""
You are an email parsing system for a DevOps API Gateway configuration workflow.

Your job is to extract API Gateway change requests from emails. Emails may be poorly formatted,
use markdown tables, plain text, code blocks, or a mix. Be flexible and extract what you can.

First decide whether this is an API Gateway change request.
Then extract all endpoint changes — both additions/updates AND deletions.

Return ONLY a valid JSON object. No markdown, no explanations, no code fences.

Rules:
- is_api_change_request: true if the email appears to be related to API Gateway configuration changes in any way; when in doubt, set to true
- environment: one of "QA", "DEV", "UAT", "PROD" if explicitly or clearly implied in any casing (e.g. "qa", "Qa", "QA" should all resolve to "QA"); otherwise null
- For endpoints_to_add (additions and updates):
  - service_name: the service name, lowercase, strip spaces (e.g. "admin-portal-service")
  - method: HTTP method in uppercase (e.g. "POST", "GET")
  - path: the full API endpoint path exactly as written. Strip any code block markers like backticks.
  - has_auth: true if "Authorization" is mentioned in the Header column or header field, false otherwise; false if the Header column is "-", blank, or does not mention Authorization
  - path_variables: list of path variable names extracted from the path (e.g. ["dealId"] from "/deals/{{dealId}}/rebook"), empty list if none
  - request_params: list of ALL request parameter names mentioned, empty list if none. Normalize casing to camelCase (e.g. "RequestId" -> "requestId")
- For endpoints_to_delete (removals):
  - service_name: the service name if mentioned, otherwise null
  - method: HTTP method in uppercase if mentioned, otherwise null
  - path: the full API endpoint path. Strip any code block markers.
- Ignore columns like "Controller" that are not relevant to API Gateway config
- Ignore @mentions, greetings, and sign-offs
- Look for deletion instructions anywhere in the email — tables, plain text sentences, bullet points.
  Phrases like "remove", "delete", "please remove", "take out" indicate a deletion.

Example output:
{{
    "is_api_change_request": true,
    "environment": "QA",
    "endpoints_to_add": [
        {{
            "service_name": "admin-portal-service",
            "method": "POST",
            "path": "/private/v1/admin/deals/{{dealId}}/rebook",
            "has_auth": true,
            "path_variables": ["dealId"],
            "request_params": ["requestId"]
        }}
    ],
    "endpoints_to_delete": [
        {{
            "service_name": "admin-portal-service",
            "method": "GET",
            "path": "/private/v1/admin/deals/search"
        }}
    ]
}}

Email Body:
{body}

Sender: {sender}
Subject: {subject}
"""

    response = client.chat.completions.create(
        model="llama-3.3-70b-versatile",
        messages=[{"role": "user", "content": prompt}],
        temperature=0,
        max_tokens=1500
    )

    text = response.choices[0].message.content.strip()

    if "```" in text:
        lines = text.split("\n")
        lines = [l for l in lines if not l.strip().startswith("```")]
        text = "\n".join(lines).strip()

    return json.loads(text)


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


def trigger_jenkins_template_export(api_type: str, environment: str) -> bool:
    """
    Trigger the Jenkins export-api-template-job with api_type and environment parameters.
    Returns True if successful, raises exception otherwise.
    """
    jenkins_url = os.environ.get('JENKINS_URL')
    jenkins_user = os.environ.get('JENKINS_USER')
    jenkins_token = os.environ.get('JENKINS_TOKEN')
    
    if not all([jenkins_url, jenkins_user, jenkins_token]):
        print("WARNING: Jenkins credentials not configured, skipping template export")
        return False
    
    env_lower = environment.lower().strip()
    api_lower = api_type.lower().strip()
    
    job_url = f"{jenkins_url}/job/export-api-template-job/buildWithParameters"
    params = {
        'API_TYPE': api_lower,
        'ENVIRONMENT': env_lower
    }
    
    try:
        response = requests.post(
            job_url,
            params=params,
            auth=(jenkins_user, jenkins_token),
            timeout=10
        )
        response.raise_for_status()
        print(f"✓ Jenkins job triggered: export-api-template-job with API_TYPE={api_lower}, ENVIRONMENT={env_lower}")
        return True
    except Exception as e:
        print(f"ERROR triggering Jenkins job: {str(e)}")
        raise


def lambda_handler(event, context):
    ses_message = event['Records'][0]['ses']
    message_id = ses_message['mail']['messageId']
    sender = ses_message['mail']['commonHeaders']['from'][0]
    subject = ses_message['mail']['commonHeaders'].get('subject', '(no subject)')

    raw = s3.get_object(
        Bucket=BUCKET,
        Key=f'raw-emails/{message_id}'
    )
    raw_email = raw['Body'].read().decode('utf-8')

    msg = email.message_from_string(raw_email)

    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                body = part.get_payload(decode=True).decode('utf-8', errors='ignore')
                break
    else:
        body = msg.get_payload(decode=True).decode('utf-8', errors='ignore')

    print("BODY:", repr(body))
    parsed = parse_email_with_ai(body, sender, subject)
    print("AI parsed result:", json.dumps(parsed, indent=2))
    is_api_change_request = bool(parsed.get('is_api_change_request', False))
    import re
    env_match = re.search(r"\b(qa|dev|uat|prod)\b", body, re.IGNORECASE)
    environment = env_match.group(1).upper() if env_match else parsed.get("environment")
    endpoints_to_add = parsed.get('endpoints_to_add', [])
    endpoints_to_delete = parsed.get('endpoints_to_delete', [])
    
    # Detect api_type (public/private) from endpoint paths
    all_endpoints = endpoints_to_add + endpoints_to_delete
    api_type = detect_api_type_from_paths(all_endpoints)
    
    template_key = resolve_template_key(environment, api_type)

    if not is_api_change_request:
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Not an API Gateway change request",
                "message_id": message_id,
                "environment": environment,
                "api_type": api_type,
                "template_key": template_key
            })
        }

    if not template_key:
        raise ValueError(f"Unable to resolve template key for environment: {environment}")

    # Trigger Jenkins to fetch the latest template from BitBucket to S3
    try:
        trigger_jenkins_template_export(api_type, environment)
    except Exception as e:
        print(f"Failed to trigger Jenkins template export: {e}")
        raise

    parsed_key = f"parsed/{message_id}.json"
    s3.put_object(
        Bucket=BUCKET,
        Key=parsed_key,
        Body=json.dumps({
            "is_api_change_request": is_api_change_request,
            "environment": environment,
            "api_type": api_type,
            "template_key": template_key,
            "endpoints_to_add": endpoints_to_add,
            "endpoints_to_delete": endpoints_to_delete
        }, indent=2),
        ContentType='application/json'
    )

    lambda_client = boto3.client('lambda')
    lambda_client.invoke(
        FunctionName=os.environ['PATCHER'],
        InvocationType='Event',
        Payload=json.dumps({
            "parsed_key": parsed_key,
            "message_id": message_id,
            "template_key": template_key,
            "environment": environment,
            "api_type": api_type
        })
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message_id": message_id,
            "environment": environment,
            "api_type": api_type,
            "template_key": template_key,
            "endpoints_to_add_count": len(endpoints_to_add),
            "endpoints_to_delete_count": len(endpoints_to_delete)
        })
    }
