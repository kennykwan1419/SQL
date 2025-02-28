WITH cleaned_addresses AS (
    SELECT 
        regexp_replace(replace('XX市浦东新区海阳路XX弄32号302室', ']', ''), '[\\-。；、：，（）【】 ();,&/]', '') AS addr1,
        regexp_replace(replace('XX市浦东新区浦电路XX弄12号101室', ']', ''), '[\\-。；、：，（）【】 ();,&/]', '') AS addr2
),split_address AS (
    SELECT
        addr1, addr2,
        -- 条件1：截取"市"之前的内容
        CASE WHEN instr(addr1, '市') > 0 THEN substr(addr1, 1, instr(addr1, '市')) ELSE addr1 END AS city_part1,
        CASE WHEN instr(addr2, '市') > 0 THEN substr(addr2, 1, instr(addr2, '市')) ELSE addr2 END AS city_part2,

        -- 条件2：截取"市"到"区"的内容
        CASE
            WHEN instr(addr1, '市') > 0 AND instr(addr1, '区') > instr(addr1, '市')
            THEN substr(addr1, instr(addr1, '市') + 1, instr(addr1, '区') - instr(addr1, '市') - 1)
            ELSE ''
        END AS district_part1,
        CASE
            WHEN instr(addr2, '市') > 0 AND instr(addr2, '区') > instr(addr2, '市')
            THEN substr(addr2, instr(addr2, '市') + 1, instr(addr2, '区') - instr(addr2, '市') - 1)
            ELSE ''
        END AS district_part2,

        -- 条件3：截取"区"之后到第一个"路/村/镇/县"的内容
        CASE
            WHEN instr(addr1, '区') > 0 THEN
                CASE
                    WHEN regexp_instr(addr1, '[路村镇县]', instr(addr1, '区')) > 0
                    THEN substr(addr1, instr(addr1, '区') + 1, regexp_instr(addr1, '[路村镇县]', instr(addr1, '区')) - instr(addr1, '区') - 1)
                    ELSE substr(addr1, instr(addr1, '区') + 1)
                END
            ELSE ''
        END AS road_part1,
        CASE
            WHEN instr(addr2, '区') > 0 THEN
                CASE
                    WHEN regexp_instr(addr2, '[路村镇县]', instr(addr2, '区')) > 0
                    THEN substr(addr2, instr(addr2, '区') + 1, regexp_instr(addr2, '[路村镇县]', instr(addr2, '区')) - instr(addr2, '区') - 1)
                    ELSE substr(addr2, instr(addr2, '区') + 1)
                END
            ELSE ''
        END AS road_part2,

        -- 条件4：截取最后一个"路/村/镇/县"之后的内容
        CASE
            WHEN instr(addr1, '区') > 0 THEN
                CASE
                    WHEN regexp_instr(addr1, '[路村镇县]', instr(addr1, '区')) > 0
                    THEN substr(addr1, regexp_instr(addr1, '[路村镇县]([^路村镇县]*)$') + 1)
                    ELSE ''
                END
            ELSE ''
        END AS last_part1,
        CASE
            WHEN instr(addr2, '区') > 0 THEN
                CASE
                    WHEN regexp_instr(addr2, '[路村镇县]', instr(addr2, '区')) > 0
                    THEN substr(addr2, regexp_instr(addr2, '[路村镇县]([^路村镇县]*)$') + 1)
                    ELSE ''
                END
            ELSE ''
        END AS last_part2
    FROM cleaned_addresses
)
,similarity_calculation AS (
    SELECT
        addr1, addr2,
        -- 条件1：任一方向市前部分100%匹配
        CASE
            WHEN city_part1 = city_part2 OR city_part2 = city_part1
            THEN 1
            ELSE 0
        END AS condition1_pass,

        -- 条件2：市区部分相似度平均值 > 90%
        CASE
            WHEN (length(district_part1) > 0 AND length(district_part2) > 0) THEN
                (CAST(length(regexp_replace(district_part1, '[^' || district_part2 || ']', '')) AS DOUBLE) / length(district_part1) +
                CAST(length(regexp_replace(district_part2, '[^' || district_part1 || ']', '')) AS DOUBLE) / length(district_part2)
            ) / 2
            ELSE 0
        END AS district_similarity,

        -- 条件3：区后到路/村/镇/县部分相似度
        CASE
            WHEN (length(road_part1) > 0 AND length(road_part2) > 0) THEN
                (CAST(length(regexp_replace(road_part1, '[^' || road_part2 || ']', '')) AS DOUBLE) / length(road_part1) +
                CAST(length(regexp_replace(road_part2, '[^' || road_part1 || ']', '')) AS DOUBLE) / length(road_part2)
            ) / 2
            ELSE 0
        END AS road_similarity,

        -- 条件4：最后一个路/村/镇/县后部分相似度
        CASE
            WHEN (length(last_part1) > 0 AND length(last_part2) > 0) THEN
                (CAST(length(regexp_replace(last_part1, '[^' || last_part2 || ']', '')) AS DOUBLE) / length(last_part1) +
                CAST(length(regexp_replace(last_part2, '[^' || last_part1 || ']', '')) AS DOUBLE) / length(last_part2)
            ) / 2
            ELSE 0
        END AS last_similarity
    FROM split_address
)
SELECT
    addr1, addr2,
    CASE
        -- 条件1不满足直接返回0
        WHEN condition1_pass = 0 THEN 0
        -- 条件2不满足返回0
        WHEN district_similarity < 0.9 THEN 0
        -- 条件3不满足返回0
        WHEN road_similarity < 0.9 THEN 0
        -- 条件4计算最终相似度
        ELSE last_similarity
    END AS final_similarity
FROM similarity_calculation;
