for GAP_H in (180, 280):
    GROUND_Y = 672
    GAP_MIN = GAP_H // 2 + 50
    GAP_MAX = GROUND_Y - GAP_H // 2 - 50
    print(
        f"GAP_H={GAP_H}: gap-center range {GAP_MIN}..{GAP_MAX} "
        f"(span {GAP_MAX - GAP_MIN}px), player clearance {GAP_H - 44}px"
    )
