#!/usr/bin/env node
// 맥 없이 CloudKit 스키마를 다룬다 (docs/06-testflight.md).
//
// 애플의 CKTool JS 는 **Node 에서 돈다** — `xcrun cktool` 과 달리 맥이 필요 없다.
// 리눅스 CI 에서 그대로 돌아간다.
//
//   node ck.mjs teams                     팀 목록 (팀 ID 확인용)
//   node ck.mjs containers                컨테이너 목록 (⚠️ 이름이 비슷한 게 여럿이다)
//   node ck.mjs export <env>              그 환경에 **지금 무엇이 있는지** 읽는다
//   node ck.mjs validate <file>           올리지 않고 문법만 검사한다
//   node ck.mjs apply <file>              Development 에 적용한다
//
// **Production 에는 올릴 수 없다.** 애플이 도구에 그 길을 안 열어 뒀다.
// Development → Production 승격은 웹 콘솔의 Deploy 버튼뿐이라 사람이 누른다.
//
// 환경 변수: CKTOOL_MGMT_TOKEN · CK_TEAM_ID · CK_CONTAINER_ID

import { readFile } from "node:fs/promises";
import { basename } from "node:path";
// CKTool JS 는 CommonJS 로 나온다. ESM 에서는 default 를 받아 풀어 써야 한다.
import cktoolDatabase from "@apple/cktool.database";
import cktoolNode from "@apple/cktool.target.nodejs";

const { CKEnvironment, PromisesApi } = cktoolDatabase;
const { File, createConfiguration } = cktoolNode;

const token = process.env.CKTOOL_MGMT_TOKEN;
if (!token) {
  console.error("CKTOOL_MGMT_TOKEN 이 없습니다. CloudKit Console → Settings → Tokens 에서 만듭니다.");
  process.exit(1);
}

const configuration = createConfiguration();
const api = new PromisesApi({
  configuration,
  security: { ManagementTokenAuth: token },
});

const teamId = process.env.CK_TEAM_ID;
const containerId = process.env.CK_CONTAINER_ID;

/** 환경 이름을 CKEnvironment 로. 기본은 development — 사고를 막는 쪽이 기본이다. */
function environmentOf(name = "development") {
  if (name === "production") return CKEnvironment.PRODUCTION;
  if (name === "development") return CKEnvironment.DEVELOPMENT;
  console.error(`환경은 development 나 production 이어야 합니다: ${name}`);
  process.exit(1);
}

function requireContainer() {
  if (teamId && containerId) return { teamId, containerId };
  console.error("CK_TEAM_ID 와 CK_CONTAINER_ID 가 필요합니다. `teams` · `containers` 로 확인하세요.");
  process.exit(1);
}

/** 오류를 사람이 읽을 수 있게 편다. 서버가 이유를 자세히 준다. */
function explain(error) {
  try {
    console.error(configuration.jsonStringify(error, null, 2));
  } catch {
    console.error(error);
  }
}

const [command, ...rest] = process.argv.slice(2);

try {
  switch (command) {
    case "teams": {
      const teams = await api.getTeams();
      for (const team of teams.teams ?? []) {
        console.log(`${team.teamId}\t${team.name ?? ""}`);
      }
      break;
    }

    case "containers": {
      if (!teamId) {
        console.error("CK_TEAM_ID 가 필요합니다. 먼저 `teams` 를 돌리세요.");
        process.exit(1);
      }
      const result = await api.getContainers({ teamId });
      // ⚠️ 이름이 비슷한 컨테이너가 여럿이면 엉뚱한 쪽을 보고 있기 쉽다.
      //    실제로 그것이 원인이었던 사례가 있다 (forums/819507).
      for (const container of result.containers ?? []) {
        console.log(container.containerId ?? JSON.stringify(container));
      }
      break;
    }

    case "export": {
      // **먼저 읽는다.** 지금 무엇이 있는지 모르고 쓰면 안 된다.
      const args = requireContainer();
      const environment = environmentOf(rest[0]);
      const result = await api.exportSchema({ ...args, environment });
      // 서버는 파일 내용을 문자열로 준다. 비어 있으면 그대로 비어 있다.
      process.stdout.write(String(result?.fileContent ?? result ?? ""));
      break;
    }

    case "validate": {
      // 올리기 전에 애플 서버로 문법을 검사한다. 이건 쓰기가 아니다.
      const args = requireContainer();
      const path = rest[0];
      if (!path) { console.error("파일 경로가 필요합니다."); process.exit(1); }
      const buffer = await readFile(path);
      await api.validateSchema({
        ...args,
        environment: CKEnvironment.DEVELOPMENT,
        file: new File([buffer], basename(path)),
      });
      console.log("문법은 통과했습니다.");
      console.log("※ 이것은 **Core Data 가 기대하는 모양인지**를 확인해 주지 않습니다.");
      console.log("   그건 시험용 컨테이너에 올려 실제로 동기화가 붙는지 봐야 압니다.");
      break;
    }

    case "apply": {
      // **Development 에만** 쓴다. Production 은 웹 콘솔의 Deploy 버튼이다.
      const args = requireContainer();
      const path = rest[0];
      if (!path) { console.error("파일 경로가 필요합니다."); process.exit(1); }
      const buffer = await readFile(path);
      const file = new File([buffer], basename(path));
      await api.importSchema({
        ...args,
        environment: CKEnvironment.DEVELOPMENT,
        file,
      });
      console.log(`${args.containerId} 의 Development 에 적용했습니다.`);
      console.log("이제 웹 콘솔에서 Deploy Schema Changes 를 눌러야 Production 에 갑니다.");
      break;
    }

    default:
      console.error("teams · containers · export · validate · apply 중 하나를 쓰세요.");
      process.exit(1);
  }
} catch (error) {
  explain(error);
  process.exit(1);
}
