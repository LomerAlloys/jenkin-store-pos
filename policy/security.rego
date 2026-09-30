package security

import future.keywords.if
import future.keywords.in

# Deny if any vulnerability has CRITICAL severity
deny[msg] if {
    vuln := input.vulnerabilities[_]
    vuln.ratings[_].severity == "critical"
    msg := sprintf("CRITICAL CVE detected: %v (%v)", [vuln.id, vuln.description])
}

# Deny if critical count metadata field exceeds 0 (from npm audit JSON)
deny[msg] if {
    input.metadata.vulnerabilities.critical > 0
    msg := sprintf("npm audit: %v critical vulnerabilities found", [input.metadata.vulnerabilities.critical])
}
