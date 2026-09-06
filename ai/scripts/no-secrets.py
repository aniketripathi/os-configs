#!/usr/bin/env python3
import sys
import json
import re

# --- CONSTANTS ---
# Regex Patterns
PATTERN_ENV_FILE = r'(?<![a-zA-Z0-9])\.env(?:[.-][a-zA-Z0-9]+)?(?![\w])'
PATTERN_ECHO_VARS = r'\b(echo|printf)\b.*\$[{]?[A-Za-z_][A-Za-z0-9_]*[}]?'
PATTERN_DUMP_VARS = r'\bprintenv\b|\benv\s*(?:[|>;]|$)|\bset\s*(?:[|>;]|$)|\bexport\s+-p\b'
PATTERN_INTERPRETER_VARS = r'\bos\.environ\b|\bprocess\.env\b|\b\$_ENV\b|\b\$_SERVER\b'
PATTERN_SECRET_FILES = r'(id_rsa|id_ed25519|id_ecdsa|.*\.pem|.*\.key|secret.*\.json|\.gnupg|secring\.gpg|rclone\.conf)'

# Reusable Messages
MSG_SUFFIX = "to avoid exposing env variables and secrets; even if it may not contain secrets."
MSG_HINT = "Hint: To safely check if a key is set without exposing it, use a conditional test. For example: if [ -n \"${VAR_NAME}\" ]; then echo 'Set'; else echo 'Not set'; fi"

# --- HELPER FUNCTIONS ---
def deny(specific_reason: str) -> dict:
    """Creates a standardized denial response formatting the reason, suffix, and AI hint."""
    full_reason = f"{specific_reason} {MSG_SUFFIX}\n{MSG_HINT}"
    return {"decision": "deny", "reason": full_reason}

def allow() -> dict:
    """Creates a standardized allow response."""
    return {"decision": "allow"}

def check_command_for_secrets(cmd: str) -> dict:
    """Checks a shell command against all secret-exposure patterns."""
    if re.search(PATTERN_ENV_FILE, cmd):
        return deny("Referencing .env files is strictly blocked")
        
    if re.search(PATTERN_ECHO_VARS, cmd):
        return deny("Echoing environment variables is blocked")
        
    if re.search(PATTERN_DUMP_VARS, cmd):
        return deny("Dumping environment variables is blocked")
        
    if re.search(PATTERN_INTERPRETER_VARS, cmd):
        return deny("Accessing env vars via script interpreters is blocked")
        
    if re.search(PATTERN_SECRET_FILES, cmd, re.IGNORECASE):
        return deny("Accessing key/pem/secret files is blocked")
        
    return allow()

def check_file_path_for_secrets(file_path: str) -> dict:
    """Checks a file path against secret file patterns."""
    if re.search(PATTERN_ENV_FILE, file_path) or re.search(PATTERN_SECRET_FILES, file_path, re.IGNORECASE):
        return deny("Accessing secret files via agent tools is blocked")
        
    return allow()

# --- MAIN LOGIC ---
def main():
    try:
        input_data = sys.stdin.read()
        if not input_data:
            print(json.dumps(allow()))
            return
            
        payload = json.loads(input_data)
        tool_call = payload.get("toolCall", {})
        tool_name = tool_call.get("name", "")
        args = tool_call.get("args", {})
        
        decision = allow()
        
        if tool_name == "run_command":
            cmd = args.get("CommandLine", "")
            decision = check_command_for_secrets(cmd)

        elif tool_name in ["view_file", "replace_file_content", "grep_search", "write_to_file"]:
            file_path = str(args.get("AbsolutePath", args.get("TargetFile", args.get("SearchPath", ""))))
            decision = check_file_path_for_secrets(file_path)
                
        print(json.dumps(decision))
        
    except Exception as e:
        # Fails open so the agent doesn't lock up entirely if the hook crashes
        print(json.dumps({"decision": "allow", "reason": f"Hook error: {str(e)}"}))

if __name__ == "__main__":
    main()
