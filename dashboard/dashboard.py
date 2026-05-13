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
from textual.screen import Screen
from textual.containers import Horizontal
from textual import on
import subprocess
import json


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
        Binding("n", "nginx_status", "Nginx", show=True),
        Binding("k", "kernel_tuning", "Tune Kernels", show=True),
    ]

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header()
        yield Static("GPU: N/A | VRAM: N/A | Load: N/A", id="status-bar")
        
        with TabbedContent(id="main-tabs"):
            with TabPane("Containers", id="tab-containers"):
                yield DataTable(id="containers-table")
            
            with TabPane("Logs", id="tab-logs"):
                yield Static("Select a container:", id="log-selector")
                yield RichLog(id="log-viewer", wrap=True, markup=True)
            
            with TabPane("Nginx", id="tab-nginx"):
                yield DataTable(id="nginx-table")
                yield RichLog(id="nginx-log", wrap=True)
            
            with TabPane("Kernel Tuning", id="tab-kernel"):
                yield Static("Kernel Tuning Status", id="kernel-status")
                yield RichLog(id="kernel-log", wrap=True)
        
        yield Footer()

    async def on_mount(self) -> None:
        """Initialize dashboard."""
        # Setup container table columns
        table = self.query_one("#containers-table", DataTable)
        table.add_columns(
            "NAME", "IMAGE", "STATUS", "PORT", "CPU", "MEM/VRAM", "UPTIME"
        )
        
        # Setup nginx table columns
        nginx_table = self.query_one("#nginx-table", DataTable)
        nginx_table.add_columns("SERVICE", "STATUS", "UPTIME", "CONNECTIONS")
        
        # Initial data load
        await self.refresh_data()
        
        # Start auto-refresh every 5 seconds
        self.set_interval(5, self.refresh_data)

    async def refresh_data(self) -> None:
        """Refresh dashboard data."""
        try:
            # Fetch container data
            result = subprocess.run(
                ["docker", "ps", "-a", "--filter", "name=sglang-", "--format", 
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
            pass
        
        # Update GPU status bar
        await self.update_gpu_status()
        
        # Update nginx status
        await self.update_nginx_status()

    async def update_gpu_status(self) -> None:
        """Update GPU status bar."""
        try:
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
                nginx_table.add_row("nginx", "Running", "Active", "N/A")
            else:
                nginx_table.add_row("nginx", "Stopped", "-", "-")
                
        except Exception:
            pass

    def action_refresh(self) -> None:
        """Manual refresh action."""
        self.refresh_data()

    def action_toggle_logs(self) -> None:
        """Toggle logs visibility."""
        tabbed = self.query_one("#main-tabs", TabbedContent)
        if tabbed.active_pane and tabbed.active_pane.id == "tab-containers":
            tabbed.active_pane = tabbed.query_one("#tab-logs", TabPane)
        else:
            tabbed.active_pane = tabbed.query_one("#tab-containers", TabPane)

    def action_nginx_status(self) -> None:
        """Switch to nginx tab."""
        tabbed = self.query_one("#main-tabs", TabbedContent)
        tabbed.active_pane = tabbed.query_one("#tab-nginx", TabPane)

    def action_kernel_tuning(self) -> None:
        """Switch to kernel tuning tab."""
        tabbed = self.query_one("#main-tabs", TabbedContent)
        tabbed.active_pane = tabbed.query_one("#tab-kernel", TabPane)


if __name__ == "__main__":
    OrchestratorDashboard().run()
