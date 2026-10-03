import pandas as pd
import matplotlib.pyplot as plt

df = pd.DataFrame({
    "method": ["benchmark", "random", "guided"],
    "coverage": [12, 18, 31]
    })

plt.figure(figsize=(6,4))
plt.bar(df["method"], df["coverage"])
plt.ylabel("Coverage bins hit")
plt.title("Dummy Coverage Comparison")
plt.tight_layout()
plt.savefig("data/plots/dummy_coverage.png")
print("Saved plot to data/plots/dummy_coverage.png")


