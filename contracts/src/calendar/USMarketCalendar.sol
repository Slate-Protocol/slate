// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMarketCalendar, Session} from "../interfaces/IMarketCalendar.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title USMarketCalendar
/// @notice NYSE/Nasdaq trading days, early closes and New York daylight saving, on-chain.
/// @dev Holidays and early closes come from NYSE's published calendar
///      (https://www.nyse.com/markets/hours-calendars) and are loaded for 2026 through 2028. The owner
///      (a timelock in deployment) can add later years and advance `coveredThrough`, but can never change a
///      day that has already started. Beyond coverage every weekday counts as a trading day, so an unlisted
///      holiday reads as stale rather than closed, which fails closed.
///
///      Daylight saving is computed for any year from the US rule in force since 2007: from 02:00 local on the
///      second Sunday of March to 02:00 local on the first Sunday of November.
///
///      Days are indexed as days since 1970-01-01 of the New York calendar date.
contract USMarketCalendar is IMarketCalendar, Ownable2Step {
    enum DayKind {
        REGULAR,
        HOLIDAY,
        EARLY_CLOSE
    }

    uint256 private constant DAY = 1 days;
    uint256 private constant HOUR = 1 hours;
    /// @dev Session times in seconds after New York midnight.
    uint256 private constant REGULAR_OPEN = 9 hours + 30 minutes;
    uint256 private constant REGULAR_CLOSE = 16 hours;
    uint256 private constant EARLY_REGULAR_CLOSE = 13 hours;
    uint256 private constant EXTENDED_CLOSE = 20 hours;
    uint256 private constant EARLY_EXTENDED_CLOSE = 17 hours;
    /// @dev The longest run of non-trading days the lookup will walk back over.
    uint256 private constant MAX_LOOKBACK_DAYS = 10;

    mapping(uint256 day => DayKind) public dayKind;
    /// @notice The last day whose holidays are known.
    uint256 public coveredThrough;

    event DaysSet(uint256[] dayList, DayKind kind);
    event CoverageExtended(uint256 coveredThrough);

    error DayAlreadyStarted(uint256 day);
    error CoverageCannotShrink();

    constructor(address owner_) Ownable(owner_) {
        uint32[29] memory holidays = [
            // 2026: Jan 1, Jan 19, Feb 16, Apr 3, May 25, Jun 19, Jul 3, Sep 7, Nov 26, Dec 25
            uint32(20_454),
            20_472,
            20_500,
            20_546,
            20_598,
            20_623,
            20_637,
            20_703,
            20_783,
            20_812,
            // 2027: Jan 1, Jan 18, Feb 15, Mar 26, May 31, Jun 18, Jul 5, Sep 6, Nov 25, Dec 24
            20_819,
            20_836,
            20_864,
            20_903,
            20_969,
            20_987,
            21_004,
            21_067,
            21_147,
            21_176,
            // 2028: Jan 17, Feb 21, Apr 14, May 29, Jun 19, Jul 4, Sep 4, Nov 23, Dec 25 (no New Year holiday)
            21_200,
            21_235,
            21_288,
            21_333,
            21_354,
            21_369,
            21_431,
            21_511,
            21_543
        ];
        // 2026: Nov 27, Dec 24. 2027: Nov 26. 2028: Jul 3, Nov 24.
        uint32[5] memory earlyCloses = [uint32(20_784), 20_811, 21_148, 21_368, 21_512];
        for (uint256 i; i < holidays.length; ++i) {
            dayKind[holidays[i]] = DayKind.HOLIDAY;
        }
        for (uint256 i; i < earlyCloses.length; ++i) {
            dayKind[earlyCloses[i]] = DayKind.EARLY_CLOSE;
        }
        coveredThrough = 21_549; // 2028-12-31
    }

    // ------------------------------------------------------------------------------------------------
    // Maintenance
    // ------------------------------------------------------------------------------------------------

    /// @notice Marks future days. Days that have started in New York can't be changed.
    function setDays(uint256[] calldata dayList, DayKind kind) external onlyOwner {
        uint256 today = _nyDay(block.timestamp);
        for (uint256 i; i < dayList.length; ++i) {
            if (dayList[i] <= today) revert DayAlreadyStarted(dayList[i]);
            dayKind[dayList[i]] = kind;
        }
        emit DaysSet(dayList, kind);
    }

    function extendCoverage(uint256 through) external onlyOwner {
        if (through <= coveredThrough) revert CoverageCannotShrink();
        coveredThrough = through;
        emit CoverageExtended(through);
    }

    // ------------------------------------------------------------------------------------------------
    // Queries
    // ------------------------------------------------------------------------------------------------

    /// @inheritdoc IMarketCalendar
    function closedSince(uint256 timestamp, Session session) public view returns (uint256) {
        // A trading day's extended session starts the evening before, so start one day ahead and walk back.
        uint256 day = timestamp / DAY + 1;
        for (uint256 i; i <= MAX_LOOKBACK_DAYS + 1 && day > 0; ++i) {
            if (isTradingDay(day)) {
                (uint256 open, uint256 close) = sessionBounds(day, session);
                if (timestamp >= close) return close;
                if (timestamp >= open) return 0;
            }
            --day;
        }
        return 0;
    }

    function isOpen(uint256 timestamp, Session session) external view returns (bool) {
        return closedSince(timestamp, session) == 0;
    }

    function isTradingDay(uint256 day) public view returns (bool) {
        uint256 weekday = (day + 4) % 7; // 0 = Sunday; 1970-01-01 was a Thursday
        return weekday != 0 && weekday != 6 && dayKind[day] != DayKind.HOLIDAY;
    }

    /// @notice The UTC open and close of `session` for New York calendar day `day`.
    function sessionBounds(uint256 day, Session session) public view returns (uint256 open, uint256 close) {
        bool early = dayKind[day] == DayKind.EARLY_CLOSE;
        if (session == Session.REGULAR) {
            open = _toUtc(day, REGULAR_OPEN);
            close = _toUtc(day, early ? EARLY_REGULAR_CLOSE : REGULAR_CLOSE);
        } else {
            open = _toUtc(day - 1, EXTENDED_CLOSE);
            close = _toUtc(day, early ? EARLY_EXTENDED_CLOSE : EXTENDED_CLOSE);
        }
    }

    /// @notice Whether New York observes daylight saving at `localSeconds` after midnight on `day`.
    function isDst(uint256 day, uint256 localSeconds) public pure returns (bool) {
        (uint256 year,,) = _civilFromDays(day);
        uint256 start = _nthSunday(year, 3, 2);
        uint256 end = _nthSunday(year, 11, 1);
        if (day < start || day > end) return false;
        if (day == start) return localSeconds >= 2 * HOUR;
        if (day == end) return localSeconds < 2 * HOUR;
        return true;
    }

    // ------------------------------------------------------------------------------------------------
    // Date arithmetic
    // ------------------------------------------------------------------------------------------------

    function _toUtc(uint256 day, uint256 localSeconds) private pure returns (uint256) {
        return day * DAY + localSeconds + (isDst(day, localSeconds) ? 4 : 5) * HOUR;
    }

    /// @dev The New York calendar day containing `timestamp`.
    function _nyDay(uint256 timestamp) private pure returns (uint256) {
        uint256 day = (timestamp - 4 * HOUR) / DAY; // EDT guess
        return isDst(day, (timestamp - 4 * HOUR) % DAY) ? day : (timestamp - 5 * HOUR) / DAY;
    }

    /// @dev Day index of the `n`th Sunday of `month` in `year`.
    function _nthSunday(uint256 year, uint256 month, uint256 n) private pure returns (uint256) {
        uint256 first = _daysFromCivil(year, month, 1);
        uint256 weekday = (first + 4) % 7;
        return first + (7 - weekday) % 7 + (n - 1) * 7;
    }

    /// @dev Howard Hinnant's days_from_civil, for dates from 1970.
    function _daysFromCivil(uint256 y, uint256 m, uint256 d) private pure returns (uint256) {
        if (m <= 2) y -= 1;
        uint256 era = y / 400;
        uint256 yoe = y - era * 400;
        uint256 doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1;
        uint256 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146_097 + doe - 719_468;
    }

    /// @dev Howard Hinnant's civil_from_days, for dates from 1970.
    function _civilFromDays(uint256 z) private pure returns (uint256 y, uint256 m, uint256 d) {
        z += 719_468;
        uint256 era = z / 146_097;
        uint256 doe = z - era * 146_097;
        uint256 yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
        y = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        d = doy - (153 * mp + 2) / 5 + 1;
        m = mp < 10 ? mp + 3 : mp - 9;
        if (m <= 2) y += 1;
    }
}
