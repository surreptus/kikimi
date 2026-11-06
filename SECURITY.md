# Security

Kikimi is a free, open-source Mac app that works on local files and sends nothing about you anywhere (see the
[privacy policy](Kikimi/Privacy.md)).

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private reporting instead: on this repository,
choose **Security > Report a vulnerability**. Include what you found, how to reproduce it and the Kikimi version
(Kikimi > About Kikimi). This is a small project maintained by one person, so replies can take a few days.

Only the latest release is supported.

## What is checked

- The Python scripts and the website's JavaScript are scanned with CodeQL, and so is the Swift in `LangCore`, on every
  push to `main` and weekly. Results are under Security > Code scanning.
- Dependabot watches GRDB, WhisperKit and the website's packages for known vulnerabilities.
- Secret scanning is on for this repository.

These checks look for common mistakes. They do not show that the code is free of problems, and the code is public so
anyone can read it.
