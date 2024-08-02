# trivy-test

Runs an security-scan on all currently configured docker-images within a cluster.
Output will be parsed:
into files named "$namespace.txt" containing the trivy-tables.
into html-files which can be deployed by gitlab-pages or similar
Metrics will be pushed daily to the pushgateway and can be configured to show up as e.g. CVEs in K8s-Namespace Dashboard.
Furthermore it will print stats into metrics.txt like this:

tivy_container_issues{namespace="abc", image="registry.gitlab.com/strowi/deploy:xyz"} 60
And export those to prometheus/pushgateway on a semi-daily basis so they can show up in K8s-Namespace Dashboard or

This shows the total of HIGH+CRITICAL security issues. There should be an alert on these metrics!

Usage

Requirements:

configured cluster
permissions to (a/ll) namespace/s
~> ./check_images.sh $K8S_CONTEXT
Ignore Issues

This script only scans for "fixable" vulnerabilities and ignores unpatched/unfixed vulnerabilities ("--ignore-unfixed" is being set).

If for some reason you still need to ignore vulnerabilities for a specific namespace, you can add it to the .trivyinore_${TEAM}_${namespace} with the normal trivy-syntax.

Example:


# Accept the risk
CVE-2018-14618

# No impact in our settings
CVE-2019-1543