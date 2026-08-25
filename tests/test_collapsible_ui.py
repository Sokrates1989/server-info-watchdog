"""Protect the compact Server Info configuration-page contract."""

from __future__ import annotations

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
WEBSITE = REPOSITORY_ROOT / "website"


class CollapsibleUiTests(unittest.TestCase):
    """Keep sections compact without dropping existing configuration controls."""

    def test_all_configuration_cards_are_collapsed_by_default(self) -> None:
        """Load the accessible card enhancer before application startup."""

        html = (WEBSITE / "index.html").read_text(encoding="utf-8")
        application = (WEBSITE / "app.js").read_text(encoding="utf-8")
        collapsible = (WEBSITE / "collapsible-cards.js").read_text(
            encoding="utf-8"
        )
        styles = (WEBSITE / "styles.css").read_text(encoding="utf-8")

        self.assertIn("collapsible-cards.js?v=collapsed-sections", html)
        self.assertIn("window.initializeCollapsibleCards?.()", application)
        self.assertIn("#config-section > .card:not(.actions)", collapsible)
        self.assertIn("setExpanded(card, false)", collapsible)
        self.assertIn("aria-expanded", collapsible)
        self.assertIn("card-collapse-body[hidden]", styles)
        self.assertIn('id="server-settings-card"', html)
        self.assertIn('id="thresholds-card"', html)

    def test_notification_controls_share_one_telegram_section(self) -> None:
        """Group routing and frequency controls without changing their IDs."""

        html = (WEBSITE / "index.html").read_text(encoding="utf-8")

        self.assertIn('id="notification-settings-card"', html)
        self.assertIn('data-collapse-summary="Telegram"', html)
        self.assertEqual(html.count("<h2>Notifications</h2>"), 1)
        for control_id in (
            "error-chat-ids",
            "warning-chat-ids",
            "info-chat-ids",
            "freq-info",
            "freq-warning",
            "freq-error",
        ):
            self.assertEqual(html.count(f'id="{control_id}"'), 1)

    def test_threshold_summary_reports_the_worst_current_state(self) -> None:
        """Show Healthy, Warning, Error, or Unavailable while collapsed."""

        application = (WEBSITE / "app.js").read_text(encoding="utf-8")
        collapsible = (WEBSITE / "collapsible-cards.js").read_text(
            encoding="utf-8"
        )

        self.assertIn("let overallStatus = 'unavailable'", application)
        self.assertIn("overallStatus = 'error'", application)
        self.assertIn("overallStatus = 'warning'", application)
        self.assertIn("overallStatus = 'ok'", application)
        self.assertIn("window.setCollapsibleCardSummary?.", application)
        self.assertIn("window.setCollapsibleCardSummary =", collapsible)

    def test_ui_and_documentation_do_not_claim_email_delivery(self) -> None:
        """Keep the browser aligned with the Telegram-only backend."""

        html = (WEBSITE / "index.html").read_text(encoding="utf-8")
        readme = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")

        self.assertNotIn('type="email"', html)
        self.assertNotIn("<option>Email</option>", html)
        self.assertIn("Telegram is currently the only delivery transport", readme)
        self.assertIn("Email and SMTP configuration", readme)


if __name__ == "__main__":
    unittest.main()
