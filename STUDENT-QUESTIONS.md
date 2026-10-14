# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:

The risk is that `burn` checks the minter's role but never asks whether the holder agreed. Someone with that role could erase another person's sUSD without returning collateral. The backing invariant would still pass because supply has fallen. In the current code, though, `Vault.redeem` only burns the caller's tokens. Ex4 uses `vm.prank(address(vault))` to show what the vault's role permits; an ordinary user cannot impersonate it.

I would make `MINTER_ROLE` responsible for minting only. A replacement `burnFrom(owner, amount)` would be limited to the redemption vault and call `_spendAllowance(owner, msg.sender, amount)` before `_burn`. The user would approve the exact sUSD amount, and `Vault.redeem` would call `stable.burnFrom(msg.sender, amount)` before returning mUSDC to that user. If either step fails, the whole redemption must revert. I would test approval, allowance reduction and rollback. This protects holders from burns they did not approve, although unbacked minting remains a separate problem.

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:

I would put `DEFAULT_ADMIN_ROLE` behind a timelock controlled by a governance multisig, so role changes need several independent signers and a delay. Only the audited vault should keep `MINTER_ROLE`, and the deployer's temporary roles should be removed after setup. A separate emergency multisig would hold `PAUSER_ROLE` so it can respond quickly.

Restarting the system should need governance approval. That requires changing the contract, since today's pauser can also unpause. This split limits what one stolen key can do, but administrators still need to be trusted: they can grant new roles. Role grants and unexpected minting should therefore be monitored.

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:

Redemption fails during a pause because `burn` reaches the same `_update` check as a transfer. I would replace `whenNotPaused` with a check that, when paused, rejects nonzero recipients but allows burns (`to == address(0)`). Minting would also stop. The role, balance and allowance checks would still apply.

The vault should burn the caller's approved tokens directly, then return mUSDC. Moving sUSD into the vault first would fail because transfers are paused. This also assumes mUSDC can still be transferred. I would check that transfers and minting fail, approved redemption works, unauthorized burns fail, and a failed payout leaves balances unchanged.

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:

In 2008, the SEC allowed the Reserve Primary Fund to suspend redemptions and delay payments from September 17 while arranging an orderly liquidation. This gave the fund time to sell assets, but investors could no longer withdraw when they wanted.

USDC needs a qualification here. Circle maintained its commitment to 1:1 redemption, but primary-market operations largely stopped over the weekend. Government protection restored access to SVB reserves, and redemption processing resumed on March 13.

For a stablecoin, reliable redemption gives traders a reason to buy below \$1 and redeem at \$1. Closing that route weakens price support, even if it slows withdrawals and forced sales. Holders may sell on exchanges instead. Keeping redemption open can support confidence, but also drains reserves faster during a run. It cannot fix missing backing. USDC's recovery involved government intervention as well, so redemption policy alone does not explain it. In the lab, pausing leaves the amount of collateral unchanged.

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:

There are two main problems: too little backing, and being unable to redeem backing that is there. Ex3 shows the first. Minting without a deposit increases supply alone, so `totalCollateral() >= totalSupply()` fails if the two started equal. Normal redemption reduces both equally and does not close the gap.

Ex4 shows the second. Pausing leaves balances unchanged, so the invariant can pass while users cannot withdraw. That uncertainty can make holders accept less than $1.

The collateral could also lose dollar value. Equal token quantities would then look safe under this invariant but would not provide full dollar backing. Ex5's price conversion helps explain this distinction. Also, `MockUSDC` has an open faucet, not real dollar reserves. Ex6 only exercises deposit/redeem sequences; passing it does not prove safe permissions or a $1 market price.

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:

The attacker calls `stable.mint(attacker, 1_000_000e6)` after receiving the role. Both tokens have six decimals, so this creates one million sUSD without depositing any mUSDC. While unpaused, `redeem` checks the vault's collateral, burns the attacker's tokens, and pays them from other users' deposits.

There must be enough collateral to redeem the full million. With only 1,000 mUSDC, that request reverts before burning. The attacker could redeem 1,000 instead and empty the vault, leaving legitimate holders unpaid. A failed redemption does not undo an earlier successful mint transaction.

The attack should have been stopped at the role grant. Only the vault should mint, after receiving collateral. The redemption balance check limits how much can leave, but cannot tell how the sUSD was created. A1's approval requirement would not help here either: the attacker would simply approve burning their own tokens to take the collateral.

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:

No. I would compare what the reserves could sell for in dollars with the amount owed to sUSD holders. Simply counting Treasury tokens would not work: Treasury prices can be above or below face value. Selling costs and any debts that must be paid first would also need to be deducted.

Someone must also verify that a custodian actually holds the securities and that they have not been pledged elsewhere. An oracle can report this information, but stale or incorrect data would make the check misleading. Holders also need a legally enforceable claim on the reserves.

Even enough assets may not mean enough cash today. Selling and settling Treasuries takes time, so the system needs a cash buffer and clear redemption terms as well as a valuation check.

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:

A practical route would be a special-purpose vehicle (SPV) that owns the building. Tokens would represent defined interests in that company, and the vault would hold those tokens as collateral.

Lawyers would need to establish the token holders' rights, check mortgages and decide who gets paid first if the property is sold. An on-chain transfer should not be assumed to change the land register. The arrangement also needs independent valuers, a property manager for rent, repairs, taxes and insurance, auditors to check the records, and a trustee or representative able to enforce claims.

The vault could no longer mint 1:1 against raw token units. Borrowing limits would depend on a cautious valuation and a workable sale process. I would keep a cash buffer, since a building cannot be sold immediately just because holders want to redeem.

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario                                       | Your test function name                           |
| ---------------------------------------------- | ------------------------------------------------- |
| Minting by a non-minter reverts                | `test_Ex4_Mint_RevertsForNonMinter`               |
| Transfers revert while paused                  | `test_Ex4_Pause_BlocksTransfers`                  |
| **Redemption** reverts while paused            | `test_Ex4_Pause_BlocksRedeem`                     |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance`        |
| ...but the vault holding `MINTER_ROLE` can     | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:

I would focus on a stolen admin key or a mistaken `MINTER_ROLE` grant. This gives an attacker a direct way to take deposits: mint sUSD without collateral, then redeem it. For example, if users deposited 1,000 mUSDC, the attacker could mint a million sUSD and redeem 1,000 to empty the vault. I would prioritize this because it gives the attacker a clear financial incentive and uses the existing mint and redeem functions.

For an additional test, I would first check that minting without the role fails and leaves balances unchanged. After granting the role, I would check that minting increases supply without adding collateral. Redeeming a million should fail, while redeeming the available 1,000 should succeed and drain the vault. This is a proposed test beyond the five Ex4 tests above.
