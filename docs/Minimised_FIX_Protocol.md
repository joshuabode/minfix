## MinFIX Message Specification

This document defines the formal message structure for the **MinFIX** protocol, a high-performance, deterministic subset of the FIX (Financial Information Exchange) protocol designed specifically for this FPGA-to-FPGA financial trading simulation project.

Check out [this](<https://en.wikipedia.org/wiki/Financial_Information_eXchange#Tagvalue_encoding_(classic_FIX)>) section on the Wikipedia page for more detail about the message encoding which inspired MinFIX.

---

### 1. Protocol Constraints

- **Encoding:** All Tags and Values are represented in **ASCII**.
- **Numerical Format:** All values (except `BeginString` and `MsgType`) are **hexadecimal strings**, fixed-width, and zero-padded.
- **Delimiter:** The pipe character `|` is used here to represent the Start of Header character which (**0x01**) is used to terminate every field.

---

### 2. Message Structure Overview

MinFIX messages follow a strict sequence to ensure **deterministic parsing** in hardware.

`8=FIX.min|35=D|38=[QTY]|44=[PRICE]|49=[CID]|54=[SIDE]|55=[TID]|`

is used for a market order and

`8=FIX.min|35=W|44=[PRICE]|55=[TID]|`

for a market data message.

---

### 3. Field Definitions

| **Tag** | **Field Name** | **Size (Bytes)** | **Format** | **Description**                                |
| ------- | -------------- | ---------------- | ---------- | ---------------------------------------------- |
| **8**   | BeginString    | 7                | `FIX.min`  | Fixed protocol identifier.                     |
| **35**  | MsgType        | 1                | `D` \|`W`  | Fixed as `D` (New Order) or `W` (Market Data). |
| **38**  | Quantity       | 3                | Hex String | The number of units (e.g., `00A` for 10).      |
| **44**  | Price          | 8                | Hex String | Price in pennies (e.g., `00FA` for 250p).      |
| **49**  | ClientID       | 1                | Hex String | Unique identifier for the source board.        |
| **54**  | Side           | 1                | `1` \|`2`  | `1` = Buy/Bid; `2` = Sell/Ask.                 |
| **55**  | TickerID       | 1                | Hex String | Unique identifier for the instrument.          |

---

### 4. Implementation Examples

#### 4.1 Trade Order Message

**Scenario:** Client `0x1` wants to **BUY** `10` units of Ticker `0xA` at a price of `255` pennies.

- **Quantity (10):** `0x00A`
- **Price (255):** `0x000000FF`
- **Client ID:** `1`
- **Side:** `1`
- **Ticker ID:** `A`

**The Wire Stream:**

`8=FIX.min|35=D|38=00A|44=000000FF|49=1|54=1|55=A|`

#### 4.2 Market Data Message

**Scenario:** The market price of Ticker `0x3` has been changed due to recent activity. Each unit now costs `378` pennies.

- **Price (378):** `0x0000017A`
- **Ticker ID:** `3`

**The Wire Stream:**

`8=FIX.min|35=W|44=0000017A|55=3|`
