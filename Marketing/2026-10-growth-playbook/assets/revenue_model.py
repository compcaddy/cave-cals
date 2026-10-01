"""Tiny 12-month cohort model behind the scenarios in 12-Metrics-and-Budget.md.

Run: python3 revenue_model.py
Assumptions are planning inputs, not forecasts. Yearly renewals begin in month 13, so they are excluded.
"""

def simulate(installs, paid_rate, yearly_price, monthly_price,
             share_yearly=0.65, apple_fee=0.15, monthly_churn=0.15, months=12):
    yearly_net = yearly_price * (1 - apple_fee)
    monthly_net = monthly_price * (1 - apple_fee)
    active_monthly = 0.0
    cash = []
    for _ in range(months):
        payers = installs * paid_rate
        active_monthly = active_monthly * (1 - monthly_churn) + payers * (1 - share_yearly)
        cash.append(payers * share_yearly * yearly_net + active_monthly * monthly_net)
    return cash

SCENARIOS = [
    ("Starter", 1_000, 0.02, 29.99, 5.99),
    ("Base", 5_000, 0.03, 29.99, 5.99),
    ("Base + pricing fix", 5_000, 0.035, 39.99, 9.99),
    ("Strong", 20_000, 0.04, 39.99, 9.99),
    ("Cal AI-lite", 60_000, 0.05, 39.99, 9.99),
]

if __name__ == "__main__":
    for name, installs, rate, yearly, monthly in SCENARIOS:
        cash = simulate(installs, rate, yearly, monthly)
        print(f"{name:20s} month 1 ${cash[0]:>9,.0f}  month 12 ${cash[-1]:>9,.0f}  year 1 ${sum(cash):>11,.0f}")
