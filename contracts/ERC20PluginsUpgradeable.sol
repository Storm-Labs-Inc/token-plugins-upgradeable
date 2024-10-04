// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { AddressArray, AddressSet } from "@1inch/solidity-utils/contracts/libraries/AddressSet.sol";
import { IERC20, ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IERC20Plugins } from "./interfaces/IERC20Plugins.sol";
import { IPlugin } from "./interfaces/IPlugin.sol";
import { ReentrancyGuardExt, ReentrancyGuardLib } from "./libs/ReentrancyGuard.sol";

/**
 * @title ERC20PluginsUpgradeable
 * @dev A base implementation of token contract to hold and manage plugins of an ERC20 token with a limited number of
 * plugins per account.
 * Each plugin is a contract that implements IPlugin interface (and/or derived from plugin).
 */
abstract contract ERC20PluginsUpgradeable is ERC20Upgradeable, IERC20Plugins, ReentrancyGuardExt {
    using AddressSet for AddressSet.Data;
    using AddressArray for AddressArray.Data;
    using ReentrancyGuardLib for ReentrancyGuardLib.Data;

    /// @custom:storage-location erc7201:storage.ERC20PluginsUpgradeable
    struct ERC20PluginsStorage {
        /// @dev Limit of plugins per account
        // solhint-disable-next-line var-name-mixedcase
        uint256 MAX_PLUGINS_PER_ACCOUNT;
        /// @dev Gas limit for a single plugin call
        // solhint-disable-next-line var-name-mixedcase
        uint256 PLUGIN_CALL_GAS_LIMIT;
        ReentrancyGuardLib.Data _guard;
        mapping(address => AddressSet.Data) _plugins;
    }

    // keccak256(abi.encode(uint256(keccak256("storage.ERC20PluginsUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line private-vars-leading-underscore,const-name-snakecase
    bytes32 private constant ERC20PluginsStorageLocation =
        0x4108db94c380a8d8a20de99d345afff9c495eeb068ca094fde639726075c9400;

    function _getERC20PluginsStorage() internal pure returns (ERC20PluginsStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := ERC20PluginsStorageLocation
        }
    }

    // solhint-disable-next-line func-name-mixedcase
    function __ERC20Plugins_init(uint256 pluginsLimit_, uint256 pluginCallGasLimit_) internal onlyInitializing {
        __ERC20Plugins_init_unchained(pluginsLimit_, pluginCallGasLimit_);
    }

    /**
     * @dev Initializer function that sets the limit of plugins per account and the gas limit for a plugin call.
     * @param pluginsLimit The limit of plugins per account.
     * @param pluginCallGasLimit The gas limit for a plugin call. Intended to prevent gas bomb attacks
     */
    // solhint-disable-next-line func-name-mixedcase
    function __ERC20Plugins_init_unchained(uint256 pluginsLimit, uint256 pluginCallGasLimit) internal {
        if (pluginsLimit == 0) revert ZeroPluginsLimit();
        ERC20PluginsStorage storage $ = _getERC20PluginsStorage();
        $.MAX_PLUGINS_PER_ACCOUNT = pluginsLimit;
        $.PLUGIN_CALL_GAS_LIMIT = pluginCallGasLimit;
        $._guard.init();
    }

    /**
     * @notice See {IERC20Plugins-MAX_PLUGINS_PER_ACCOUNT}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function MAX_PLUGINS_PER_ACCOUNT() public view virtual returns (uint256) {
        return _getERC20PluginsStorage().MAX_PLUGINS_PER_ACCOUNT;
    }

    /**
     * @notice See {IERC20Plugins-PLUGIN_CALL_GAS_LIMIT}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function PLUGIN_CALL_GAS_LIMIT() public view virtual returns (uint256) {
        return _getERC20PluginsStorage().PLUGIN_CALL_GAS_LIMIT;
    }

    /**
     * @notice See {IERC20Plugins-hasPlugin}.
     */
    function hasPlugin(address account, address plugin) public view virtual returns (bool) {
        return _getERC20PluginsStorage()._plugins[account].contains(plugin);
    }

    /**
     * @notice See {IERC20Plugins-pluginsCount}.
     */
    function pluginsCount(address account) public view virtual returns (uint256) {
        return _getERC20PluginsStorage()._plugins[account].length();
    }

    /**
     * @notice See {IERC20Plugins-pluginAt}.
     */
    function pluginAt(address account, uint256 index) public view virtual returns (address) {
        return _getERC20PluginsStorage()._plugins[account].at(index);
    }

    /**
     * @notice See {IERC20Plugins-plugins}.
     */
    function plugins(address account) public view virtual returns (address[] memory) {
        return _getERC20PluginsStorage()._plugins[account].items.get();
    }

    /**
     * @dev Returns the balance of a given account.
     * @param account The address of the account.
     * @return balance The account balance.
     */
    function balanceOf(address account)
        public
        view
        virtual
        override(IERC20, ERC20Upgradeable)
        nonReentrantView(_getERC20PluginsStorage()._guard)
        returns (uint256)
    {
        return super.balanceOf(account);
    }

    /**
     * @notice See {IERC20Plugins-pluginBalanceOf}.
     */
    function pluginBalanceOf(
        address plugin,
        address account
    )
        public
        view
        virtual
        nonReentrantView(_getERC20PluginsStorage()._guard)
        returns (uint256)
    {
        if (hasPlugin(account, plugin)) {
            return super.balanceOf(account);
        }
        return 0;
    }

    /**
     * @notice See {IERC20Plugins-addPlugin}.
     */
    function addPlugin(address plugin) public virtual {
        _addPlugin(msg.sender, plugin);
    }

    /**
     * @notice See {IERC20Plugins-removePlugin}.
     */
    function removePlugin(address plugin) public virtual {
        _removePlugin(msg.sender, plugin);
    }

    /**
     * @notice See {IERC20Plugins-removeAllPlugins}.
     */
    function removeAllPlugins() public virtual {
        _removeAllPlugins(msg.sender);
    }

    function _addPlugin(address account, address plugin) internal virtual {
        if (plugin == address(0)) revert InvalidPluginAddress();
        if (IPlugin(plugin).TOKEN() != IERC20Plugins(address(this))) revert InvalidTokenInPlugin();
        ERC20PluginsStorage storage $ = _getERC20PluginsStorage();
        if (!$._plugins[account].add(plugin)) revert PluginAlreadyAdded();
        if ($._plugins[account].length() > $.MAX_PLUGINS_PER_ACCOUNT) revert PluginsLimitReachedForAccount();

        emit PluginAdded(account, plugin);
        uint256 balance = balanceOf(account);
        if (balance > 0) {
            _updateBalances(plugin, address(0), account, balance);
        }
    }

    function _removePlugin(address account, address plugin) internal virtual {
        if (!_getERC20PluginsStorage()._plugins[account].remove(plugin)) revert PluginNotFound();

        emit PluginRemoved(account, plugin);
        uint256 balance = balanceOf(account);
        if (balance > 0) {
            _updateBalances(plugin, account, address(0), balance);
        }
    }

    function _removeAllPlugins(address account) internal virtual {
        ERC20PluginsStorage storage $ = _getERC20PluginsStorage();
        address[] memory pluginItems = $._plugins[account].items.get();
        uint256 balance = balanceOf(account);
        unchecked {
            for (uint256 i = pluginItems.length; i > 0; i--) {
                address item = pluginItems[i - 1];
                $._plugins[account].remove(item);
                emit PluginRemoved(account, item);
                if (balance > 0) {
                    _updateBalances(item, account, address(0), balance);
                }
            }
        }
    }

    /// @notice Assembly implementation of the gas limited call to avoid return gas bomb,
    // moreover call to a destructed plugin would also revert even inside try-catch block in Solidity 0.8.17
    /// @dev try IPlugin(plugin).updateBalances{gas: _PLUGIN_CALL_GAS_LIMIT}(from, to, amount) {} catch {}
    function _updateBalances(address plugin, address from, address to, uint256 amount) private {
        bytes4 selector = IPlugin.updateBalances.selector;
        uint256 gasLimit = _getERC20PluginsStorage().PLUGIN_CALL_GAS_LIMIT;
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, selector)
            mstore(add(ptr, 0x04), from)
            mstore(add(ptr, 0x24), to)
            mstore(add(ptr, 0x44), amount)

            let gasLeft := gas()
            if iszero(call(gasLimit, plugin, 0, ptr, 0x64, 0, 0)) {
                if lt(div(mul(gasLeft, 63), 64), gasLimit) {
                    returndatacopy(ptr, 0, returndatasize())
                    revert(ptr, returndatasize())
                }
            }
        }
    }

    function _update(
        address from,
        address to,
        uint256 amount
    )
        internal
        virtual
        override
        nonReentrant(_getERC20PluginsStorage()._guard)
    {
        super._update(from, to, amount);

        unchecked {
            if (amount > 0 && from != to) {
                ERC20PluginsStorage storage $ = _getERC20PluginsStorage();
                address[] memory pluginsFrom = $._plugins[from].items.get();
                address[] memory pluginsTo = $._plugins[to].items.get();
                uint256 pluginsFromLength = pluginsFrom.length;
                uint256 pluginsToLength = pluginsTo.length;

                for (uint256 i = 0; i < pluginsFromLength; i++) {
                    address plugin = pluginsFrom[i];

                    uint256 j;
                    for (j = 0; j < pluginsToLength; j++) {
                        if (plugin == pluginsTo[j]) {
                            // Both parties are participating in the same plugin
                            _updateBalances(plugin, from, to, amount);
                            pluginsTo[j] = address(0);
                            break;
                        }
                    }

                    if (j == pluginsToLength) {
                        // Sender is participating in a plugin, but receiver is not
                        _updateBalances(plugin, from, address(0), amount);
                    }
                }

                for (uint256 j = 0; j < pluginsToLength; j++) {
                    address plugin = pluginsTo[j];
                    if (plugin != address(0)) {
                        // Receiver is participating in a plugin, but sender is not
                        _updateBalances(plugin, address(0), to, amount);
                    }
                }
            }
        }
    }
}
