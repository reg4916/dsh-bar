/**
 * DSH Bar — browser half.
 *
 * The native app cannot deep-link into a session: the GUI has no session URL.
 * Instead the plugin holds a "focus wish" and this page half opens it through
 * ctx.uiWorkspace.openSession. Polling is deliberately tiny and same-origin;
 * the first response only arms the wish so a stale one cannot steal focus on
 * page load.
 */
window.__ModuleLoader__.load({
	id: "dsh-bar",
	factory: () => {
		const POLL_MS = 400;
		const CLIENT_HEADER = "x-dsh-bar-client";

		let lastFocusAt = 0;
		let armed = false;

		async function poll(ctx) {
			let data;
			try {
				const response = await fetch("/dsh-bar/pending-focus", {
					headers: { [CLIENT_HEADER]: "1", "content-type": "application/json" },
					cache: "no-store",
				});
				if (!response.ok) return;
				data = await response.json();
			} catch {
				return;
			}
			const focus = data?.focus;
			if (!focus || typeof focus.at !== "number" || typeof focus.sessionId !== "string") return;
			if (!armed) {
				armed = true;
				lastFocusAt = focus.at;
				return;
			}
			if (focus.at <= lastFocusAt) return;
			lastFocusAt = focus.at;
			try {
				ctx.uiWorkspace?.openSession?.(focus.sessionId);
				window.focus();
			} catch {
				/* the session may have been disposed in the meantime */
			}
		}

		return {
			inject: ["@deepseek-ai/dsh-client-ui-workspace"],
			apply(ctx) {
				ctx.effect(() => {
					const timer = setInterval(() => poll(ctx), POLL_MS);
					return () => clearInterval(timer);
				}, "dsh-bar: focus polling");
			},
		};
	},
});
