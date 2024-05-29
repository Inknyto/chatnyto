import json
import sys
from tqdm import tqdm


# Define the vcard format
vcard_template = """BEGIN:VCARD
VERSION:3.0
FN:{display_name}
N:{last_name};{first_name};;;
TEL;TYPE=CELL:{phone_number}
END:VCARD
"""

# Parse the JSON data
with open('group_members.txt') as f:
    data = f.read().split('\n')

numctx = 1
# Extract the relevant information
def extract(data, numctx):
    display_name = f"chatnyto_member_{numctx}"
    phone_number = data
    first_name = display_name
    last_name = display_name

    # Populate the vcard format
    vcard_entry = vcard_template.format(
        display_name=display_name,
        first_name=first_name,
        last_name=last_name,
        phone_number=phone_number
    )
    numctx+=1
    return vcard_entry

cleaned = []
for d in tqdm(data):
    try:
        if str(int(d)).isnumeric():
            cleaned.append(extract(d, numctx))
    except:
        pass

with open('group_members.vcf', 'w') as f:
    f.write('\n'.join(cleaned))
