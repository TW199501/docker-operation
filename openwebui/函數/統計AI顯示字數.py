from pydantic import BaseModel, Field
from typing import Optional
import re


class Filter:
    class Valves(BaseModel):
        pass

    def __init__(self):
        self.valves = self.Valves()
        self.count_pattern = re.compile(
            r"\[當前提示\]:在上輪對話中，系統統計你的生成字數為：\d+"
        )
        self.chinese_pattern = re.compile(r"[\u4e00-\u9fff]")

    def count_chinese_chars(self, text: str) -> int:
        return len(self.chinese_pattern.findall(text))

    def inlet(self, body: dict, __user__: Optional[dict] = None) -> dict:
        if not isinstance(body, dict) or "messages" not in body:
            return body

        messages = body.get("messages", [])
        if not messages:
            return body

        # 查找最新助理消息
        last_assistant_msg = next(
            (msg for msg in reversed(messages) if msg.get("role") == "assistant"), None
        )

        # 統計字數
        count = 0
        if last_assistant_msg:
            content = last_assistant_msg.get("content", "")
            count = self.count_chinese_chars(content)

        # 構造統計信息
        count_info = f"[當前提示]:在上輪對話中，系統統計你的生成字數為：{count}"

        # 查找系統消息
        system_message = next(
            (msg for msg in messages if msg.get("role") == "system"), None
        )

        # 更新系統消息
        if system_message:
            content = system_message.get("content", "")
            # 移除所有舊統計
            cleaned_content = self.count_pattern.sub("", content).strip()
            # 保留原始內容並追加新統計
            system_message["content"] = f"{cleaned_content}\n{count_info}".strip()
        else:
            messages.insert(0, {"role": "system", "content": count_info})

        return body

    def outlet(self, body: dict, __user__: Optional[dict] = None) -> dict:
        return body
