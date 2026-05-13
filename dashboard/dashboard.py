#!/usr/bin/env python3
"""SGLang Orchestrator Dashboard - Textual TUI"""

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import (
    DataTable,
    Header,
    Footer,
    TabbedContent,
    TabPane,
    RichLog,
    Static,
)


class OrchestratorDashboard(App):
    """Main dashboard application."""

    CSS = """
    Screen {
        layout: grid;
        grid-size: 1;
        grid-gutter: 1;
    }
    
    #status-bar {
        height: 1;
        background: $boost;
        color: $text;
        content-align: center middle;
    }
    
    DataTable {
        height: 12;
    }
    
    RichLog {
        height: 1fr;
        border: solid $accent;
        padding: 1;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit", show=True),
        Binding("r", "refresh", "Refresh", show=True),
        Binding("l", "toggle_logs", "Toggle Logs", show=True),
    ]

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header()
        yield Static("GPU: N/A | VRAM: N/A | Load: N/A", id="status-bar")
        yield TabbedContent(initial="containers")
        yield Footer()

    async def on_mount(self) -> None:
        """Initialize dashboard."""
        # Setup containers tab
        containers_pane = TabPane("Containers", id="containers-pane")
        containers_pane.compose_children = self._compose_containers
        
        # Setup logs tab
        logs_pane = TabPane("Logs", id="logs-pane")
        logs_pane.compose_children = self._compose_logs
        
        tabbed = self.query_one(TabbedContent)
        tabbed.mount(containers_pane)
        tabbed.mount(logs_pane)
        
        # Initial data load
        await self.refresh_data()
        
        # Start auto-refresh every 5 seconds
        self.set_interval(5, self.refresh_data)

    def _compose_containers(self) -> ComposeResult:
        """Compose containers tab."""
        table = DataTable(id="containers-table")
        table.add_columns(
            "NAME", "IMAGE", "STATUS", "PORT", "CPU", "MEM/VRAM", "UPTIME"
        )
        yield table

    def _compose_logs(self) -> ComposeResult:
        """Compose logs tab."""
        yield RichLog(id="log-viewer", wrap=True, markup=True)

    async def refresh_data(self) -> None:
        """Refresh dashboard data."""
        try:
            import subprocess
            import json
            
            # Fetch container data
            result = subprocess.run(
                ["docker", "ps", "--filter", "name=sglang-", "--format", 
                 "{{json .}}"],
                capture_output=True, text=True, timeout=5
            )
            
            if result.returncode == 0 and result.stdout.strip():
                table = self.query_one("#containers-table", DataTable)
                table.clear()
                
                for line in result.stdout.strip().split("\n"):
                    if not line:
                        continue
                    try:
                        data = json.loads(line)
                        table.add_row(
                            data.get("Names", "unknown"),
                            data.get("Image", "unknown"),
                            data.get("Status", "unknown"),
                            data.get("Ports", ""),
                            data.get("CPUPerc", "0%"),
                            data.get("MemUsage", "N/A"),
                            data.get("RunningFor", "0s")
                        )
                    except json.JSONDecodeError:
                        pass
        
        except Exception as e:
            # Silently handle errors - dashboard stays responsive
            pass
        
        # Update GPU status bar
        try:
            import subprocess
            result = subprocess.run(
                ["nvidia-smi", "--query-gpu=temperature.gpu,power.draw,power.limit,utilization.gpu", 
                 "--format=csv,noheader"],
                capture_output=True, text=True, timeout=3
            )
            if result.returncode == 0:
                gpu_info = result.stdout.strip()
                self.query_one("#status-bar", Static).update(
                    f"GPU: {gpu_info}"
                )
        except Exception:
            pass

    def action_refresh(self) -> None:
        """Manual refresh action."""
        self.refresh_data()

    def action_toggle_logs(self) -> None:
        """Toggle logs visibility."""
        tabbed = self.query_one(TabbedContent)
        if tabbed.active == "containers":
            tabbed.active = "logs"
        else:
            tabbed.active = "containers"


if __name__ == "__main__":
    OrchestratorDashboard().run()
