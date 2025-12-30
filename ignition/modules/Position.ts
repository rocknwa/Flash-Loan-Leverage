import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("PositionModule", (m) => {
  const position = m.contract("Position");
  return { position };
});
