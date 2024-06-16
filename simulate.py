import plotly.graph_objects as go

def getPrice(supply, amount):
    scaled_supply = supply//10**18
    scaled_amount = amount//10**18
    sum1 = 0
    if scaled_supply != 0:
        sum1 = (scaled_supply - 1) * (scaled_supply) * (2 * (scaled_supply - 1) + 1) / 6
    sum2 = (scaled_supply + scaled_amount - 1) * (scaled_supply + scaled_amount) * (2 * (scaled_supply + scaled_amount - 1) + 1) / 6
    summation = sum2 - sum1
    return summation * 10**18//9_600_000_000_000

input_lst = [
    (i * 10**21, 1000*10**18)
    for i in range(1000)
]
supply = [val[0]/10**18 for val in input_lst]
price = [getPrice(val[0], 10**18)/10**18 for val in input_lst]

fig = go.Figure();
fig.add_trace(go.Scatter(x=supply, y=price, mode='lines+markers', name='Quadratic Bonding Curve (P(x) = x^2/320000000000)'))

fig.update_layout(
    title='Supply vs Price Quadratic Bonding Curve (P(x) = x^2/9,600,000,000,000)',
    xaxis_title='Supply',
    yaxis_title='Price (ETH)',
    template='plotly_dark'
)

fig.show()