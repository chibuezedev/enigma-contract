mod mock_erc20;
use starknet::ContractAddress;


#[starknet::interface]
trait ICDPVault<TContractState> {
    fn deposit_collateral(ref self: TContractState, amount: u256);
    fn borrow(ref self: TContractState, amount: u256);
    fn repay(ref self: TContractState, amount: u256);
    fn withdraw_collateral(ref self: TContractState, amount: u256);
    fn liquidate(ref self: TContractState, user: ContractAddress);
    fn get_position(self: @TContractState, user: ContractAddress) -> (u256, u256);
    fn get_health_factor(self: @TContractState, user: ContractAddress) -> u256;
    fn get_btc_price(self: @TContractState) -> u256;
    fn set_btc_price(ref self: TContractState, price: u256);
    fn get_collateral_token(self: @TContractState) -> ContractAddress;
    fn get_debt_token(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod CDPVault {
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    // LTV = 150% (collateral must be 1.5x debt), precision 1e18
    const MIN_COLLATERAL_RATIO: u256 = 1500000000000000000;
    // Liquidation threshold 120%
    const LIQUIDATION_THRESHOLD: u256 = 1200000000000000000;
    const PRECISION: u256 = 1000000000000000000;
    // Liquidation bonus 10%
    const LIQUIDATION_BONUS: u256 = 100000000000000000;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        collateral_token: ContractAddress,
        debt_token: ContractAddress,
        // mocked BTC price in USD with 18 decimals
        btc_price: u256,
        // user -> collateral deposited
        collateral: Map<ContractAddress, u256>,
        // user -> debt outstanding
        debt: Map<ContractAddress, u256>,
        // privacy: position hash commitment (pedersen of collateral+debt+salt)
        position_commitment: Map<ContractAddress, felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CollateralDeposited: CollateralDeposited,
        Borrowed: Borrowed,
        Repaid: Repaid,
        CollateralWithdrawn: CollateralWithdrawn,
        Liquidated: Liquidated,
        CommitmentUpdated: CommitmentUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct CollateralDeposited {
        #[key]
        user: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Borrowed {
        #[key]
        user: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Repaid {
        #[key]
        user: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct CollateralWithdrawn {
        #[key]
        user: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Liquidated {
        #[key]
        user: ContractAddress,
        liquidator: ContractAddress,
        debt_covered: u256,
        collateral_seized: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct CommitmentUpdated {
        #[key]
        user: ContractAddress,
        commitment: felt252,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        collateral_token: ContractAddress,
        debt_token: ContractAddress,
        initial_btc_price: u256,
    ) {
        self.owner.write(owner);
        self.collateral_token.write(collateral_token);
        self.debt_token.write(debt_token);
        self.btc_price.write(initial_btc_price);
    }

    #[abi(embed_v0)]
    impl CDPVaultImpl of super::ICDPVault<ContractState> {
        fn deposit_collateral(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'amount must be > 0');
            let caller = get_caller_address();
            let token = IERC20Dispatcher { contract_address: self.collateral_token.read() };
            token.transfer_from(caller, get_contract_address(), amount);

            let current = self.collateral.entry(caller).read();
            self.collateral.entry(caller).write(current + amount);

            self._update_commitment(caller);
            self.emit(CollateralDeposited { user: caller, amount });
        }

        fn borrow(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'amount must be > 0');
            let caller = get_caller_address();

            let current_debt = self.debt.entry(caller).read();
            let new_debt = current_debt + amount;
            self.debt.entry(caller).write(new_debt);

            assert(
                self._get_collateral_ratio(caller) >= MIN_COLLATERAL_RATIO, 'under-collateralized',
            );

            let token = IERC20Dispatcher { contract_address: self.debt_token.read() };
            token.transfer(caller, amount);

            self._update_commitment(caller);
            self.emit(Borrowed { user: caller, amount });
        }

        fn repay(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let current_debt = self.debt.entry(caller).read();
            assert(current_debt > 0, 'no debt to repay');

            let repay_amount = if amount > current_debt {
                current_debt
            } else {
                amount
            };
            let token = IERC20Dispatcher { contract_address: self.debt_token.read() };
            token.transfer_from(caller, get_contract_address(), repay_amount);

            self.debt.entry(caller).write(current_debt - repay_amount);
            self._update_commitment(caller);
            self.emit(Repaid { user: caller, amount: repay_amount });
        }

        fn withdraw_collateral(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let current_collateral = self.collateral.entry(caller).read();
            assert(current_collateral >= amount, 'insufficient collateral');

            self.collateral.entry(caller).write(current_collateral - amount);

            let debt = self.debt.entry(caller).read();
            if debt > 0 {
                assert(
                    self._get_collateral_ratio(caller) >= MIN_COLLATERAL_RATIO,
                    'would under-collateralize',
                );
            }

            let token = IERC20Dispatcher { contract_address: self.collateral_token.read() };
            token.transfer(caller, amount);

            self._update_commitment(caller);
            self.emit(CollateralWithdrawn { user: caller, amount });
        }

        fn liquidate(ref self: ContractState, user: ContractAddress) {
            let ratio = self._get_collateral_ratio(user);
            assert(ratio < LIQUIDATION_THRESHOLD, 'position is healthy');

            let liquidator = get_caller_address();
            let debt = self.debt.entry(user).read();
            assert(debt > 0, 'no debt');

            let price = self.btc_price.read();
            // collateral to seize = debt_value / btc_price * (1 + bonus)
            let debt_value = debt;
            let collateral_to_seize = (debt_value * (PRECISION + LIQUIDATION_BONUS)) / price;

            let user_collateral = self.collateral.entry(user).read();
            let actual_seized = if collateral_to_seize > user_collateral {
                user_collateral
            } else {
                collateral_to_seize
            };

            let debt_token = IERC20Dispatcher { contract_address: self.debt_token.read() };
            debt_token.transfer_from(liquidator, get_contract_address(), debt);

            self.debt.entry(user).write(0);
            self.collateral.entry(user).write(user_collateral - actual_seized);

            let collateral_token = IERC20Dispatcher {
                contract_address: self.collateral_token.read(),
            };
            collateral_token.transfer(liquidator, actual_seized);

            self._update_commitment(user);
            self
                .emit(
                    Liquidated {
                        user, liquidator, debt_covered: debt, collateral_seized: actual_seized,
                    },
                );
        }

        fn get_position(self: @ContractState, user: ContractAddress) -> (u256, u256) {
            (self.collateral.entry(user).read(), self.debt.entry(user).read())
        }

        fn get_health_factor(self: @ContractState, user: ContractAddress) -> u256 {
            let debt = self.debt.entry(user).read();
            if debt == 0 {
                return 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff_u256;
            }
            self._get_collateral_ratio(user)
        }

        fn get_btc_price(self: @ContractState) -> u256 {
            self.btc_price.read()
        }

        fn set_btc_price(ref self: ContractState, price: u256) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'only owner');
            assert(price > 0, 'price must be > 0');
            self.btc_price.write(price);
        }

        fn get_collateral_token(self: @ContractState) -> ContractAddress {
            self.collateral_token.read()
        }

        fn get_debt_token(self: @ContractState) -> ContractAddress {
            self.debt_token.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _get_collateral_ratio(self: @ContractState, user: ContractAddress) -> u256 {
            let debt = self.debt.entry(user).read();
            if debt == 0 {
                return 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff_u256;
            }
            let collateral = self.collateral.entry(user).read();
            let price = self.btc_price.read();
            let collateral_scaled = collateral * 10000000000_u256;
            let collateral_value = (collateral_scaled * price) / PRECISION;
            (collateral_value * PRECISION) / debt
        }

        fn _update_commitment(ref self: ContractState, user: ContractAddress) {
            let collateral = self.collateral.entry(user).read();
            let debt = self.debt.entry(user).read();
            // simple pedersen-like commitment: hash(collateral_low, debt_low)
            let c_low: felt252 = (collateral & 0xffffffffffffffffffffffffffffffff_u256)
                .try_into()
                .unwrap();
            let d_low: felt252 = (debt & 0xffffffffffffffffffffffffffffffff_u256)
                .try_into()
                .unwrap();
            let commitment = core::pedersen::pedersen(c_low, d_low);
            self.position_commitment.entry(user).write(commitment);
            self.emit(CommitmentUpdated { user, commitment });
        }
    }
}
