<p align="center">
  <img src="assets/branding/logo.png" width="96" height="96" alt="CF Monitor logo">
</p>

<h1 align="center">CF Monitor</h1>

<p align="center">Your servers. Always in view.</p>
<p align="center">A Flutter client for CF-Server-Monitor, built for iOS and Android.</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a><br>
  Flutter · iOS / Android · <a href="LICENSE">MIT License</a>
</p>

![CF Monitor: multiple sites, live server metrics, resource history, and network quality](docs/images/showcase.png)

<p align="center"><sub>Actual Flutter pages rendered with demo data. Light and dark themes shown; no production credentials or server data are used.</sub></p>

## Monitor on the move

- **Multiple sites, one app.** Add public or private sites, keep credentials separate, and choose a default site to open at launch.
- **A live view of your fleet.** Follow online status, CPU, RAM, disk, bandwidth, monthly traffic, and remaining value. Switch between cards and a compact list, with group and region filters.
- **History that you can explore.** Inspect resource trends from 10 minutes to 7 days, toggle chart series, and touch a chart to read samples. Optional GPU and disk I/O metrics appear when available.
- **Network quality at a glance.** Check latency and packet loss for the site's configured routes.
- **Server setup from your phone.** Sign in to add or delete servers, generate probe installation commands for supported systems, and choose a GitHub proxy.
- **Made for everyday use.** English and Simplified Chinese, light/dark/system appearance, saved display preferences, WebSocket reconnection, and refresh after returning to the app.

## Upstream project

CF Monitor connects to [huilang-me/CF-Server-Monitor](https://github.com/huilang-me/CF-Server-Monitor). Thanks to the upstream project for its server monitoring service and APIs.

## License

The mobile client and its original logo are available under the [MIT License](LICENSE). The upstream project's copyright and license notices are retained in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and bundled in the app.
