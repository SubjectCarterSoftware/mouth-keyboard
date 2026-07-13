import XCTest
@testable import TypeLessBuddy

final class RewriteModelLimitsTests: XCTestCase {

    private func gb(_ value: Double) -> SystemRAMProfile {
        SystemRAMProfile(totalBytes: UInt64(value * 1_073_741_824))
    }

    // MARK: - 24 GB (the dev machine)

    func test_24GB_2B_hitsPracticalInputCap() {
        let limits = RewriteModelLimits.compute(tier: .standard2B, ramProfile: gb(24))
        XCTAssertTrue(limits.isFeasible)
        XCTAssertEqual(limits.maxInputTokens, RewriteModelLimits.practicalInputCap)
        XCTAssertEqual(limits.maxOutputTokens, RewriteModelLimits.outputCap)
        XCTAssertGreaterThanOrEqual(limits.promptWordLimit, 20_000)
    }

    func test_24GB_4B_hitsPracticalInputCap() {
        let limits = RewriteModelLimits.compute(tier: .standard4B, ramProfile: gb(24))
        XCTAssertTrue(limits.isFeasible)
        XCTAssertEqual(limits.maxInputTokens, RewriteModelLimits.practicalInputCap)
        XCTAssertEqual(limits.maxOutputTokens, RewriteModelLimits.outputCap)
    }

    func test_24GB_9B_hitsPracticalInputCap() {
        let limits = RewriteModelLimits.compute(tier: .high9B, ramProfile: gb(24))
        XCTAssertTrue(limits.isFeasible)
        XCTAssertEqual(limits.maxInputTokens, RewriteModelLimits.practicalInputCap)
        XCTAssertEqual(limits.maxOutputTokens, RewriteModelLimits.outputCap)
    }

    // MARK: - 16 GB (typical median Mac)

    func test_16GB_2B_capBound() {
        let limits = RewriteModelLimits.compute(tier: .standard2B, ramProfile: gb(16))
        XCTAssertTrue(limits.isFeasible)
        XCTAssertEqual(limits.maxInputTokens, RewriteModelLimits.practicalInputCap)
    }

    func test_16GB_9B_ramBoundButFeasible() {
        let limits = RewriteModelLimits.compute(tier: .high9B, ramProfile: gb(16))
        XCTAssertTrue(limits.isFeasible)
        XCTAssertGreaterThanOrEqual(limits.maxInputTokens, 8_192)
        XCTAssertGreaterThanOrEqual(limits.maxOutputTokens, 2_048)
    }

    // MARK: - 8 GB (minimum supported)

    func test_8GB_2B_feasibleWithReducedInput() {
        let limits = RewriteModelLimits.compute(tier: .standard2B, ramProfile: gb(8))
        XCTAssertTrue(limits.isFeasible)
        XCTAssertGreaterThanOrEqual(limits.maxInputTokens, 2_048)
    }

    func test_8GB_9B_refused() {
        let limits = RewriteModelLimits.compute(tier: .high9B, ramProfile: gb(8))
        XCTAssertFalse(limits.isFeasible)
    }

    // MARK: - 4 GB (low-end, refuse everything large)

    func test_4GB_9B_refused() {
        let limits = RewriteModelLimits.compute(tier: .high9B, ramProfile: gb(4))
        XCTAssertFalse(limits.isFeasible)
    }

    // MARK: - Invariants

    func test_outputNeverExceedsCap_acrossAllProfiles() {
        for ramGB in stride(from: 8.0, through: 64.0, by: 8.0) {
            for tier in RewriteModelTier.allCases {
                let limits = RewriteModelLimits.compute(tier: tier, ramProfile: gb(ramGB))
                guard limits.isFeasible else { continue }
                XCTAssertLessThanOrEqual(
                    limits.maxOutputTokens,
                    RewriteModelLimits.outputCap,
                    "\(tier) @ \(ramGB) GB exceeded output cap"
                )
                XCTAssertLessThanOrEqual(
                    limits.maxInputTokens,
                    RewriteModelLimits.practicalInputCap,
                    "\(tier) @ \(ramGB) GB exceeded input cap"
                )
                XCTAssertEqual(
                    limits.maxKVSize,
                    limits.maxInputTokens + limits.maxOutputTokens,
                    "\(tier) @ \(ramGB) GB KV size should equal in+out"
                )
            }
        }
    }

    // MARK: - Beats the old hardcoded limits everywhere it's feasible

    func test_newLimits_dominateOldHardcoded_onMedianHardware() {
        let oldOutputCaps: [RewriteModelTier: Int] = [
            .standard2B: 1_024,
            .standard4B: 1_536,
            .high9B: 2_048,
        ]
        let oldWordLimits: [RewriteModelTier: Int] = [
            .standard2B: 1_000,
            .standard4B: 1_500,
            .high9B: 2_000,
        ]
        for tier in RewriteModelTier.allCases {
            let limits = RewriteModelLimits.compute(tier: tier, ramProfile: gb(16))
            guard limits.isFeasible else { continue }
            XCTAssertGreaterThan(
                limits.maxOutputTokens,
                oldOutputCaps[tier]!,
                "\(tier) output should beat old hardcoded cap on 16 GB"
            )
            XCTAssertGreaterThan(
                limits.promptWordLimit,
                oldWordLimits[tier]!,
                "\(tier) word limit should beat old hardcoded cap on 16 GB"
            )
        }
    }
}
