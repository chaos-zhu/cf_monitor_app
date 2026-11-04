# CF Monitor Privacy Policy

Effective date: November 4, 2026

CF Monitor is an open-source mobile client for CF-Server-Monitor. You choose the
monitoring sites it connects to. The app does not require an account with its
developer and does not include advertising, analytics, or tracking SDKs.

## Information used by the app

- The app stores the names and addresses of sites you add, your settings, and
  cached exchange rates on your device.
- If you sign in to a site, your username and password are sent to that site to
  authenticate. The app does not save the password. The resulting sign-in token
  is stored in the device's secure storage and sent to that site when needed.
- Server status, resource usage, network metrics, and other information are
  retrieved from the monitoring site you choose and displayed in the app.

The app connects directly to your chosen site, including through a WebSocket for
live updates. The site's operator controls its own data collection, retention,
and security practices. The developer of CF Monitor does not operate your site
merely because you use the app. We recommend using HTTPS for your site.

## Third-party services

To obtain exchange rates, the app may request rates from Frankfurter and, if
necessary, ExchangeRate-API. These services receive the network information
normally included in a request, such as your IP address. Site credentials and
authorization tokens are not sent to these exchange-rate services.

The app can generate probe installation commands containing links to GitHub or a
proxy selected by you. Running such a command is a separate action, and those
services have their own privacy practices.

## Your choices and contact

You can remove a site from the app, which also removes its locally stored token,
or remove local app data using your device's settings. Removing a site from the
app does not delete data held by the monitoring site or other services.

For privacy questions, contact the project through its public issue tracker:
https://github.com/chaos-zhu/cf_monitor_app/issues. Please do not post passwords,
tokens, or other sensitive information in a public issue.

## Changes

We may update this policy when the app changes. The current version will be
available at this location, with an updated effective date when appropriate.
