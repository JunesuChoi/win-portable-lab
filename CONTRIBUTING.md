# Contributing

1. Keep KO/EN script and guide text in sync.
2. Add or update one file under manifests/tools for every package version.
3. Pin SHA-256 and document source trust, risk, update strategy, and redistribution status.
4. Never make a stress, erase, dirty-state, driver-removal, tuning, or reboot action automatic.
5. Run ./scripts/Test-Repository.ps1 -Root $PWD -Language en and the Pester suite.

Do not commit third-party binaries. Submit package-definition changes separately from GUI or recommendation-engine changes so reviewers can audit the supply chain.
