# Security policy

FaultCanvas is a test/development tool, not an internet-facing production
gateway. The competition MVP defaults to a loopback listener and only accepts
`http://` upstream URLs. It does not implement TLS interception.

Do not put production credentials in scenario bodies or headers. The runtime
journal is bounded, but operators remain responsible for controlling access to
reports and configuration files.

Please report vulnerabilities privately to the repository owner rather than
opening a public issue with exploit details.
