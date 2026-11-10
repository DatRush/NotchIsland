# Weather checks

Run `bash Checks/Weather/run.sh` on macOS. The checks use an isolated preferences suite and URLProtocol responses; they do not contact Open-Meteo or change the user's city.

Coverage: decoding, invalid and stale data, day/night icons, search escaping, Celsius, caching, refresh throttling, failed requests, city changes during requests, disabling weather, search cancellation and rate limits. UI layout and live service availability require separate checks.
