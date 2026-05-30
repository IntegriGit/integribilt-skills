# monitor

Infrastructure health overview across the IntegriBilt environment.

## What I do
I pull a comprehensive health snapshot: Zabbix problem count, Prometheus alert state, Grafana dashboard status, container health in Portainer, and any recent log spikes in Loki. I present a concise status report with red/amber/green indicators.

## How to use me
Say "monitor" or "health check" and I will run through all systems and give you a status summary. You can also ask about a specific system: "monitor postgres" or "monitor docker".

## Tools I use
- zabbix MCP for infrastructure monitoring
- prometheus MCP for metrics
- grafana MCP for dashboards
- portainer / docker MCP for container health
- loki / elastic MCP for log anomalies
