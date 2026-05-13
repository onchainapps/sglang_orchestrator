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
    Button,
    Switch,
)
from textual.screen import Screen
from textual.containers import Horizontal
from textual import on


class ContainerDetailsScreen(Screen):
    """Container details screen with model info and controls."""

    BINDINGS = [
        Binding("escape", "pop_screen", "Back"),
    ]

    def __init__(self, container_name: str):
        super().__init__()
        self.container_name = container_name

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(f"Container: {self.container_name}", id="detail-title")
        yield Static("", id="model-info")
        yield Horizontal(
            Button("Restart", id="restart-btn"),
            Button("Stop", id="stop-btn"),
            Button("Logs", id="logs-btn"),
            Button("Back", id="back-btn"),
            id="controls"
        )
        yield Footer()


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
    
    #controls {
        dock: bottom;
        width: 100%;
        height: 3;
        align: center middle;
    }
    
    #model-info {
        border: solid $accent;
        padding: 1;
        height: auto;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit", show=True),
        Binding("r", "refresh", "Refresh", show=True),
        Binding("l", "toggle_logs", "Toggle Logs", show=True),
        Binding("d", "details", "Details", show=True),
        Binding("n", "nginx_status", "Nginx", show=True),
        Binding("k", "kernel_tuning", "Tune Kernels", show=True),
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
        containers_pane.mount(DataTable(id="containers-table"))
        
        # Setup logs tab
        logs_pane = TabPane("Logs", id="logs-pane")
        logs_pane.mount(
            Static("Select a container:", id="log-selector"),
            RichLog(id="log-viewer", wrap=True, markup=True)
        )
        
        # Setup nginx status tab
        nginx_pane = TabPane("Nginx", id="nginx-pane")
        nginx_pane.mount(
            DataTable(id="nginx-table"),
            RichLog(id="nginx-log", wrap=True)
        )
        
        # Setup kernel tuning tab
        kernel_pane = TabPane("Kernel Tuning", id="kernel-pane")
        kernel_pane.mount(
            Static("Kernel Tuning Status", id="kernel-status"),
            RichLog(id="kernel-log", wrap=True)
        )
        
        tabbed = self.query_one(TabbedContent)
        tabbed.mount(containers_pane)
        tabbed.mount(logs_pane)
        tabbed.mount(nginx_pane)
        tabbed.mount(kernel_pane)
        
        # Initial data load
        await self.refresh_data()
        
        # Start auto-refresh every 5 seconds
        self.set_interval(5, self.refresh_data)

    async def refresh_data(self) -> None:
        """Refresh dashboard data."""
        try:
            import subprocess
            import json
            
            # Fetch container data
            result = subprocess.run(
                ["docker", "ps", "-a", "--filter", "name=sglang-", "--format", 
                 "{{json .}}"],
                capture_output=True, text=True, timeout=5
            )
            
            if result.returncode == 0 and result.stdout.strip():
                table = self.query_one("#containers-table", DataTable)
                table.clear()
                table.add_columns(
                    "NAME", "IMAGE", "STATUS", "PORT", "CPU", "MEM/VRAM", "UPTIME"
                )
                
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
            pass
        
        # Update GPU status bar
        await self.update_gpu_status()
        
        # Update nginx status
        await self.update_nginx_status()

    async def update_gpu_status(self) -> None:
        """Update GPU status bar."""
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

    async def update_nginx_status(self) -> None:
        """Update nginx status."""
        try:
            import subprocess
            
            # Check if nginx is running
            result = subprocess.run(
                ["systemctl", "is-active", "nginx"],
                capture_output=True, text=True, timeout=3
            )
            
            nginx_status = "Running" if result.returncode == 0 else "Stopped"
            
            # Update nginx table
            nginx_table = self.query_one("#nginx-table", DataTable)
            nginx_table.clear()
            nginx_table.add_columns("SERVICE", "STATUS", "UPTIME", "CONNECTIONS")
            
            if nginx_status == "Running":
                # Get nginx uptime
                uptime_result = subprocess.run(
                    ["systemctl", "status", "nginx"],
                    capture_output=True, text=True, timeout=3
                )
                uptime = "N/A"
                for line in uptime_result.stdout.split("\n"):
                    if "Active:" in line:
                        uptime = line.split("Active:")[1].strip() if "Active:" in line else "N/A"
                        break
                
                # Get connections (from nginx status page if enabled)
                connections = "N/A"
                try:
                    import httpx
                    async with httpx.AsyncClient() as client:
                        response = await client.get("http://localhost/nginx_status", timeout=2)
                        if response.status_code == 200:
                            connections = response.text.split("\n")[2].strip() if "Active connections:" in response.text else "N/A"
                except Exception:
                    pass
                
                nginx_table.add_row("nginx", "Running", uptime, connections)
            else:
                nginx_table.add_row("nginx", "Stopped", "-", "-")
                
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

    def action_details(self) -> None:
        """Show container details."""
        try:
            import subprocess
            result = subprocess.run(
                ["docker", "ps", "--filter", "name=sglang-", "--format", "{{.Names}}"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                containers = result.stdout.strip().split("\n")
                if containers:
                    self.push_screen(ContainerDetailsScreen(containers[0]))
        except Exception:
            pass

    def action_nginx_status(self) -> None:
        """Switch to nginx tab."""
        tabbed = self.query_one(TabbedContent)
        tabbed.active = "nginx"

    def action_kernel_tuning(self) -> None:
        """Switch to kernel tuning tab."""
        tabbed = self.query_one(TabbedContent)
        tabbed.active = "kernel"


if __name__ == "__main__":
    OrchestratorDashboard().run()
