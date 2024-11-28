// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import "../external/chainlink/ILogAutomation.sol";
import {Common} from "../external/chainlink/Common.sol";
import {IFeeManager} from "../external/chainlink/IFeeManager.sol";
import {IRewardManager} from "../external/chainlink/IRewardManager.sol";
import {IVerifierFeeManager} from "../external/chainlink/IVerifierFeeManager.sol";
import {IVerifierProxy} from "../external/chainlink/IVerifierProxy.sol";
import {StreamsLookupCompatibleInterface} from "../external/chainlink/StreamsLookupCompatibleInterface.sol";
import {IDatastreamOracle} from "../interfaces/IDatastreamOracle.sol";
import {IOracle} from "../interfaces/IOracle.sol";

contract DatastreamOracle is
    IDatastreamOracle,
    Ownable2Step,
    ILogAutomation,
    StreamsLookupCompatibleInterface,
    UUPSUpgradeable,
    Initializable
{
    string public constant STRING_DATASTREAMS_FEEDLABEL = "feedIDs";
    string public constant STRING_DATASTREAMS_QUERYLABEL = "timestamp";

    IVerifierProxy public immutable verifier;
    bytes32[] internal _feedIds;
    mapping(bytes32 => FeedData) public _feedData;
    mapping(address => uint256) internal _assetToPrice;
    address public fallbackOracle;
    address public forwarder;
    mapping(address => bool) public isOperator;
    uint256 public requestBitmap;

    modifier onlyOperator() {
        if (!isOperator[msg.sender]) revert NotOperator();
        _;
    }

    constructor(address verifier_) Ownable(msg.sender) {
        verifier = IVerifierProxy(verifier_);
    }

    function initialize(address owner_) external initializer {
        _transferOwnership(owner_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function feeToken() public view returns (address) {
        return IFeeManager(address(verifier.s_feeManager())).i_linkAddress();
    }

    function feeBalance() external view returns (uint256) {
        return IERC20(feeToken()).balanceOf(address(this));
    }

    function feedData(bytes32 feedId) external view returns (FeedData memory) {
        return _feedData[feedId];
    }

    function checkLog(Log calldata log, bytes memory) external view returns (bool, bytes memory) {
        uint256 length = _feedIds.length;
        string[] memory stringFeedIds = new string[](length);
        uint256 bitmap = requestBitmap;
        uint256 l = 0;
        for (uint256 i = 0; i < length; ++i) {
            if ((bitmap >> i) & 1 == 0) {
                continue;
            }
            stringFeedIds[l] = Strings.toHexString(uint256(_feedIds[i]), 32);
            ++l;
        }
        assembly {
            mstore(stringFeedIds, l)
        }
        revert StreamsLookup(
            STRING_DATASTREAMS_FEEDLABEL, stringFeedIds, STRING_DATASTREAMS_QUERYLABEL, log.timestamp, ""
        );
    }

    /**
     * @notice this is a new, optional function in streams lookup. It is meant to surface streams lookup errors.
     * @return upkeepNeeded boolean to indicate whether the keeper should call performUpkeep or not.
     * @return performData bytes that the keeper should call performUpkeep with, if
     * upkeep is needed. If you would like to encode data to decode later, try `abi.encode`.
     */
    function checkErrorHandler(uint256, /*errCode*/ bytes memory /*extraData*/ )
        external
        pure
        returns (bool, bytes memory)
    {
        return (true, "0");
        // Hardcoded to always perform upkeep.
        // Read the StreamsLookup error handler guide for more information.
        // https://docs.chain.link/chainlink-automation/guides/streams-lookup-error-handler
    }

    // The Data Streams report bytes is passed here.
    // extraData is context data from feed lookup process.
    // Your contract may include logic to further process this data.
    // This method is intended only to be simulated offchain by Automation.
    // The data returned will then be passed by Automation into performUpkeep
    function checkCallback(bytes[] calldata values, bytes calldata extraData)
        external
        pure
        returns (bool, bytes memory)
    {
        return (true, abi.encode(values, extraData));
    }

    function performUpkeep(bytes calldata performData) external {
        if (msg.sender != forwarder) revert InvalidForwarder();

        // Decode the performData bytes passed in by CL Automation.
        // This contains the data returned by your implementation in checkCallback().
        (bytes[] memory signedReports,) = abi.decode(performData, (bytes[], bytes));

        IFeeManager feeManager = IFeeManager(address(verifier.s_feeManager()));
        IRewardManager rewardManager = IRewardManager(address(feeManager.i_rewardManager()));

        address feeTokenAddress = feeManager.i_linkAddress();

        for (uint256 i = 0; i < signedReports.length; ++i) {
            bytes memory unverifiedReport = signedReports[i];

            (, /* bytes32[3] reportContextData */ bytes memory reportData) =
                abi.decode(unverifiedReport, (bytes32[3], bytes));

            // Report verification fees
            (Common.Asset memory fee,,) = feeManager.getFeeAndReward(address(this), reportData, feeTokenAddress);

            // Approve rewardManager to spend this contract's balance in fees
            if (fee.amount > 0) {
                IERC20(feeTokenAddress).approve(address(rewardManager), fee.amount);
            }

            // Verify the report
            bytes memory verifiedReportData = verifier.verify(unverifiedReport, abi.encode(feeTokenAddress));

            // Decode verified report data into a Report struct
            Report memory verifiedReport = abi.decode(verifiedReportData, (Report));

            address asset = _feedData[verifiedReport.feedId].asset;
            if (verifiedReport.price < 0) revert InvalidReport();
            _assetToPrice[asset] = uint256(uint192(verifiedReport.price));

            // Log price from report
            emit SetPrice(asset, uint256(uint192(verifiedReport.price)));
        }

        // Reset rewardManager's approval to spend this contract's balance in fees
        IERC20(feeTokenAddress).approve(address(rewardManager), 0);
    }

    function setFeed(bytes32 feedId, address asset) external onlyOwner {
        FeedData memory data = _feedData[feedId];
        data.asset = asset;
        if (data.index == 0) {
            data.index = uint96(_feedIds.length + 1);
            _feedIds.push(feedId);
        }
        _feedData[feedId] = data;
        emit SetFeed(data.asset, feedId, data.index);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function getAssetPrice(address asset) public view returns (uint256 price) {
        price = _assetToPrice[asset];
        if (price == 0) {
            return IOracle(fallbackOracle).getAssetPrice(asset);
        }
    }

    function getAssetsPrices(address[] memory assets) external view returns (uint256[] memory prices) {
        prices = new uint256[](assets.length);
        unchecked {
            for (uint256 i = 0; i < assets.length; ++i) {
                prices[i] = getAssetPrice(assets[i]);
            }
        }
    }

    function setForwarder(address newForwarder) external onlyOwner {
        forwarder = newForwarder;
        emit SetForwarder(newForwarder);
    }

    function setOperator(address operator, bool status) external onlyOwner {
        isOperator[operator] = status;
        emit SetOperator(operator, status);
    }

    function request(uint256 bitmap) external onlyOperator {
        requestBitmap = bitmap;
        emit Request(msg.sender, bitmap);
    }

    function getFeedIds() external view returns (bytes32[] memory) {
        return _feedIds;
    }

    function getAllFeedData() external view returns (bytes32[] memory feedIds, FeedData[] memory data) {
        feedIds = _feedIds;
        uint256 length = feedIds.length;
        data = new FeedData[](length);
        for (uint256 i = 0; i < length; ++i) {
            data[i] = _feedData[feedIds[i]];
        }
    }

    function setFallbackOracle(address newFallbackOracle) external onlyOwner {
        fallbackOracle = newFallbackOracle;
        emit SetFallbackOracle(newFallbackOracle);
    }
}
