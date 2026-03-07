import json
import asyncio
import os
from generated_client.client import Client
from generated_client.exceptions import GraphQLClientGraphQLMultiError


async def main():
    api_url = os.getenv("API_URL", "http://127.0.0.1:8000/graphql")
    client = Client( url=api_url )

    RED    = "\033[38;5;196m"
    GREEN  = "\033[38;5;46m"
    GREEN2 = "\033[32m"
    BLUE   = "\033[38;5;33m"
    CYAN   = "\033[38;5;51m"
    GREY   = "\033[38;5;245m"
    RESET  = "\033[0m"

    employee_id              = 4711
    employee_name            = "Max"
    employee_surname         = "Mustermann"
    employee_description     = "EG15"
    employee_description_new = "EG16"


    logo = r"""
▄▖         ▜     ▄▖  ▗ ▌       ▄▖▜ ▘    ▗
▙▖▚▘▀▌▛▛▌▛▌▐ █▌  ▙▌▌▌▜▘▛▌▛▌▛▌  ▌ ▐ ▌█▌▛▌▜▘
▙▖▞▖█▌▌▌▌▙▌▐▖▙▖  ▌ ▙▌▐▖▌▌▙▌▌▌  ▙▖▐▖▌▙▖▌▌▐▖
         ▌         ▄▌
    """

    print("\n\n" + GREEN + logo + RESET)

    # -------------------------------------------------
    # ADD
    # -------------------------------------------------
    try:
        print( f"\n{CYAN}⭐ Adding employee {employee_id} ({employee_name} {employee_surname}, {employee_description})..." + RESET )
        result = await client.add_employee(
            employee_id=employee_id,
            name=employee_name,
            surname=employee_surname,
            description=employee_description
        )
        result_json = result.model_dump_json( indent=2 )
        data = json.loads( result_json )
        print( "\n" + GREEN2 + "" + data["add_employee"] + RESET )

    except GraphQLClientGraphQLMultiError as e:
        print( RED + "\n❌ Add failed:" + RESET, e )

    # -------------------------------------------------
    # UPDATE
    # -------------------------------------------------
    try:
        print( f"\n{CYAN}⭐ Updating employee {employee_id} ({employee_name} {employee_surname}, {employee_description}) to become {employee_description_new}..." + RESET )
        result = await client.update_employee(
            employee_id=employee_id,
            name=employee_name,
            surname=employee_surname,
            description=employee_description_new
        )

        result_json = result.model_dump_json( indent=2 )
        data = json.loads( result_json )
        print( "\n" + GREEN2 + "" + data["update_employee"] + RESET )

    except GraphQLClientGraphQLMultiError as e:
        print( RED + "\n❌ Update failed:" + RESET, e )

    # -------------------------------------------------
    # READ ALL
    # -------------------------------------------------
    try:
        print( CYAN + "\n⭐ Fetching all employees..." + RESET )
        result = await client.get_employees()

        result_json = result.model_dump_json( indent=2 )
        print( "\n" + GREEN2 + "" + result_json + RESET )

    except GraphQLClientGraphQLMultiError as e:
        print( RED + "\n❌ Read failed:" + RESET, e )

    # -------------------------------------------------
    # DELETE
    # -------------------------------------------------
    try:
        print( f"\n{CYAN}⭐ Deleting employee {employee_id} ({employee_name} {employee_surname}, {employee_description_new})..." + RESET )
        result = await client.delete_employee(
            employee_id = employee_id
        )

        result_json = result.model_dump_json( indent=2 )
        data = json.loads( result_json )
        print( "\n" + GREEN2 + "" + data["delete_employee"] + RESET )

    except GraphQLClientGraphQLMultiError as e:
        print( RED + "\n❌ Delete failed:" + RESET, e )

    print( GREEN + "\n✅ Done.\n\n\n" + RESET )

    # -------------------------------------------------
    # GET employee by surname
    # -------------------------------------------------
#    try:
#        print( CYAN + "\n⭐ Getting employee by surname..." + RESET )
#        result = await client.get_employee_by_surname( employee_surname )
#
#        result_json = result.model_dump_json( indent=2 )
#        print( "\n" + GREEN2 + "" + result_json + RESET )
#
#    except GraphQLClientGraphQLMultiError as e:
#        print( RED + "\n❌ Get failed:" + RESET, e )

if __name__ == "__main__":
    asyncio.run( main() )
