import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import os

import argparse

plt.rcParams["figure.figsize"] = [40, 30]

from pandas.plotting import register_matplotlib_converters

register_matplotlib_converters()


def readStats(name: str):
    df = pd.read_csv(name).convert_dtypes()
    # at least one item - let it lag in the beginning until we reach the min
    # block number or the table will be empty
    df.set_index("block_number", inplace=True)
    df.time /= 1000000000
    df.drop(columns=["gas"], inplace=True)
    df["bps"] = df.blocks / df.time
    df["tps"] = df.txs / df.time
    return df


def prettySecs(s: float):
    sa = abs(int(s))
    ss = sa % 60
    m = sa // 60 % 60
    h = sa // (60 * 60)
    sign = "" if s >= 0 else "-"

    if h > 0:
        return f"{sign}{h}h{m}m{ss}s"
    elif m > 0:
        return f"{sign}{m}m{ss}s"
    else:
        return f"{sign}{ss}s"


def formatBins(df: pd.DataFrame, bins: int):
    if bins > 0:
        bins = np.linspace(
            df.block_number.iloc[0] - df.blocks.iloc[0],
            df.block_number.iloc[-1],
            bins,
            dtype=int,
        )
        return df.groupby(pd.cut(df["block_number"], bins), observed=True)
    else:
        return df


parser = argparse.ArgumentParser()
parser.add_argument("baseline")
parser.add_argument("contender")
parser.add_argument("--plot", action="store_true")
parser.add_argument(
    "--bins",
    default=10,
    type=int,
    help="Number of bins to group block ranges into in overview, 0=all rows",
)
parser.add_argument(
    "--min-block-number",
    default=500000,
    type=int,
    help="Skip block blocks below the given number",
)
args = parser.parse_args()
min_block_number = args.min_block_number

baseline = readStats(args.baseline)
contender = readStats(args.contender)

start = max(min(baseline.index), min(contender.index))
end = min(max(baseline.index), max(contender.index))

baseline = baseline.loc[baseline.index >= start and baseline.index <= end]
contender = contender.loc[contender.index >= start and contender.index <= end]

# Join the two frames then interpolate - this helps dealing with runs that
# haven't been using the same chunking and/or max-blocks
df = baseline.merge(contender, on=("block_number", "blocks"), how="outer")
df = df.interpolate(method="index").reindex(contender.index)
df.reset_index(inplace=True)

if df.block_number.iloc[-1] > min_block_number + df.block_number.iloc[0]:
    cutoff = min(
        df.block_number.iloc[-1] - min_block_number,
        min_block_number,
    )
    df = df[df.block_number >= cutoff]

df["bpsd"] = (df.bps_y - df.bps_x) / df.bps_x
df["tpsd"] = (df.tps_y - df.tps_x) / df.tps_x.replace(0, 1)
df["timed"] = (df.time_y - df.time_x) / df.time_x

if args.plot:
    plt.rcParams["axes.grid"] = True

    fig = plt.figure()
    bps = fig.add_subplot(2, 2, 1, title="Blocks per second (more is better)")
    bpsd = fig.add_subplot(2, 2, 2, title="Difference (>0 is better)")
    tps = fig.add_subplot(2, 2, 3, title="Transactions per second (more is better)")
    tpsd = fig.add_subplot(2, 2, 4, title="Difference (>0 is better)")

    bps.plot(df.block_number, df.bps_x.rolling(3).mean(), label="baseline")
    bps.plot(df.block_number, df.bps_y.rolling(3).mean(), label="contender")

    bpsd.plot(df.block_number, df.bpsd.rolling(3).mean())

    tps.plot(df.block_number, df.tps_x.rolling(3).mean(), label="baseline")
    tps.plot(df.block_number, df.tps_y.rolling(3).mean(), label="contender")

    tpsd.plot(df.block_number, df.tpsd.rolling(3).mean())

    bps.legend()
    tps.legend()

    fig.subplots_adjust(bottom=0.05, right=0.95, top=0.95, left=0.05)
    plt.show()


print(f"{os.path.basename(args.baseline)} vs {os.path.basename(args.contender)}")
print(
    formatBins(df, args.bins)
    .agg(
        dict.fromkeys(["bps_x", "bps_y", "tps_x", "tps_y"], "mean")
        | dict.fromkeys(["time_x", "time_y"], "sum")
        | dict.fromkeys(["bpsd", "tpsd", "timed"], "mean")
    )
    .to_string(
        formatters=dict.fromkeys(["bpsd", "tpsd", "timed"], "{:,.2%}".format)
        | dict.fromkeys(["bps_x", "bps_y", "tps_x", "tps_y"], "{:,.2f}".format)
        | dict.fromkeys(["time_x", "time_y"], prettySecs),
    )
)

print(
    f"\nblocks: {df.block_number.max() - df.block_number.min()}, baseline: {prettySecs(df.time_x.sum())}, contender: {prettySecs(df.time_y.sum())}"
)
time_xt = df.time_x.sum()
time_yt = df.time_y.sum()

timet = time_yt - df.time_x.sum()
print(f"Time (total): {prettySecs(timet)}, {(timet/time_xt):.2%}")

print()
print(
    "bpsd = blocks per sec diff (+), tpsd = txs per sec diff, timed = time to process diff (-)"
)
print("+ = more is better, - = less is better")
