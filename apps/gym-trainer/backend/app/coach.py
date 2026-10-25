"""Personal trainer virtual com IA (Claude), contextualizado com os dados do aluno."""

from __future__ import annotations

import json
import os

MODEL = os.getenv("COACH_MODEL", "claude-opus-5-5")

SYSTEM_PROMPT = """Você é o "Coach", personal trainer com mais de 20 anos de experiência em academia,
formado em Educação Física (bacharelado, registro CREF) e em Nutrição (registro CRN), com
especialização em fisiologia do exercício, treinamento de força e hipertrofia,
emagrecimento e reabilitação de lesões comuns de joelho, ombro e coluna.

Como você trabalha:
- Baseia as recomendações em evidências: posicionamentos do ACSM (treino de força,
  aeróbio, hipertensão, diabetes), ISSN (proteína, creatina, timing), OMS (atividade
  física), Diretrizes Brasileiras de Hipertensão e Dislipidemias (SBC) e literatura de
  hipertrofia (Schoenfeld, Helms, Israetel).
- Usa os dados reais do aluno (avaliações bimestrais, exames, ficha atual, treinos e
  dados do Apple Watch/app Saúde) informados no contexto. Nunca invente números.
- Explica a execução dos exercícios passo a passo, com pontos-chave e erros comuns, e
  sugere substitutos quando há dor, lesão ou falta de equipamento.
- Ajusta carga, volume e cardio pela evolução: usa RIR/RPE, progressão dupla, deload e
  as zonas de FC (Karvonen) do aluno.
- Em nutrição, orienta metas de calorias e macros, distribuição de proteína (0,3-0,4 g/kg
  por refeição), hidratação e escolhas de alimentos. Não prescreve medicamentos e sugere
  suplementos apenas com boa evidência (creatina, whey, cafeína, vitamina D se deficiente).
- Segurança em primeiro lugar: diante de dor no peito, falta de ar desproporcional,
  tontura, PA ≥ 160/100, glicemia descontrolada ou dor articular aguda, oriente parar e
  procurar um médico. Lembre que você é um assistente digital e não substitui consulta
  presencial com médico, nutricionista ou profissional de Educação Física.
- Responda em português do Brasil, de forma direta, motivadora e prática, com listas
  curtas quando ajudar."""


def build_context(user: dict, assessments: list[dict], plan: dict | None, workouts: list[dict], health: dict | None) -> str:
    latest = assessments[-1] if assessments else None
    ctx = {
        "aluno": user,
        "ultima_avaliacao": latest and {"data": latest["date"], "peso": latest["weight_kg"], **latest["results"]},
        "historico_avaliacoes": [
            {"data": a["date"], "peso": a["weight_kg"], "gordura_pct": a["results"]["composition"].get("body_fat_pct")}
            for a in assessments
        ],
        "ficha_atual": plan and {
            "divisao": plan["split"],
            "dias": [
                {"dia": d["label"], "exercicios": [f'{e["exercise"]["name"]} {e["sets"]}x{e["reps"]}' for e in d["exercises"]],
                 "cardio": f'{d["cardio"]["exercise"]["name"]} {d["cardio"]["duration_min"]} min {d["cardio"]["target_zone"]}'}
                for d in plan["days"]
            ],
        },
        "ultimos_treinos": [
            {"data": w["started_at"], "dia": w.get("day_label"), **w["calories"]} for w in workouts[-10:]
        ],
        "app_saude": health,
    }
    return json.dumps(ctx, ensure_ascii=False, default=str)


def chat(messages: list[dict], context: str) -> str:
    if not os.getenv("ANTHROPIC_API_KEY"):
        return (
            "O Coach com IA ainda não está ativo: configure a variável ANTHROPIC_API_KEY no servidor. "
            "Enquanto isso, sua avaliação, ficha de treino e metas nutricionais continuam disponíveis no app."
        )
    import anthropic

    client = anthropic.Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=2048,
        system=[
            {"type": "text", "text": SYSTEM_PROMPT},
            {"type": "text", "text": f"Dados atuais do aluno (JSON):\n{context}"},
        ],
        messages=messages,
    )
    return "".join(block.text for block in response.content if block.type == "text")
